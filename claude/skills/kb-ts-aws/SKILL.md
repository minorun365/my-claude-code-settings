---
name: kb-ts-aws
description: AWSトラブルシューティング。Cognito/AgentCore/Bedrock/Amplify/CDK/CloudWatch等
user-invocable: true
---

# AWS トラブルシューティング

AWS関連で遭遇した問題と解決策を記録する。

## Cognito認証: client_id mismatch

**症状**: `Claim 'client_id' value mismatch with configuration.`

**原因**: IDトークンを使用していたが、APIがアクセストークンの`client_id`クレームを検証していた

**解決策**: アクセストークンを使用する
```typescript
// NG
const idToken = session.tokens?.idToken?.toString();

// OK
const accessToken = session.tokens?.accessToken?.toString();
```

## AgentCore JWT: DiscoveryUrl バリデーションエラー

**症状**: `Properties validation failed for resource ... DiscoveryUrl: string [...] does not match pattern ^.+/\.well-known/openid-configuration$`

**原因**: `usingJWT` の `discoveryUrl` に issuer URL のみを渡していた（末尾の `/.well-known/openid-configuration` が欠落）

**解決策**: フルパスで指定する
```typescript
// NG
`https://cognito-idp.${region}.amazonaws.com/${userPoolId}`

// OK
`https://cognito-idp.${region}.amazonaws.com/${userPoolId}/.well-known/openid-configuration`
```

## Bedrock Model Detector: 重複通知メール

**症状**: 新モデルリリース時に同じモデルの通知メールが複数回届く

**原因**: DynamoDBの「上書き保存」方式 + リリース直後のAPI不安定性の組み合わせ

1. T=0: APIに新モデル出現 → 検出・通知 → DynamoDBに保存
2. T=5: APIから一時的にモデルが消失 → DynamoDBをモデルなしで上書き
3. T=10: APIに再出現 → 再び「新モデル」として検出 → 重複通知

**解決策**: DynamoDBの保存を和集合（union）方式に変更。一度検出されたモデルはDBから消えないようにする

```python
# NG: APIの応答でそのまま上書き（モデルが消えるとDBからも消える）
save_models(region, current_models)

# OK: 前回のデータとの和集合で保存（一度検出されたモデルは残る）
save_models(region, current_models | previous_models)
```

**教訓**: 定期ポーリング型の差分検知では、外部APIの一時的な不安定性を考慮し、累積方式でデータを保持する。

## CDK Lambda: ARM64バンドリングでImportModuleError

**症状**: Lambda実行時に `ImportModuleError` が発生（pydantic_core等のネイティブバイナリ）

**原因**: Lambdaに `architecture: ARM_64` を指定したが、バンドリング時の `platform` が一致していない

**解決策**: Lambda定義とバンドリングの両方でARM64を指定

```typescript
const fn = new lambda.Function(this, 'MyFunction', {
  runtime: lambda.Runtime.PYTHON_3_13,
  architecture: lambda.Architecture.ARM_64,  // ARM64を指定
  code: lambda.Code.fromAsset(path.join(__dirname, '../lambda'), {
    bundling: {
      image: lambda.Runtime.PYTHON_3_13.bundlingImage,
      platform: "linux/arm64",  // ← これが必要！
      command: [
        "bash", "-c",
        "pip install -r requirements.txt -t /asset-output && cp *.py /asset-output",
      ],
    },
  }),
});
```

## AgentCore Identity: workload-identity ARN 不一致

**症状**: `@requires_access_token` で `GetResourceOauth2Token` の権限エラー。IAMポリシーには `GetResourceOauth2Token` が設定済み

**原因**: `agentcore deploy` で `.agentcore.json` がパッケージに含まれると、ローカルで自動生成された workload identity ID（例: `workload-383171e1`）が使われる。IAMポリシーのリソースARNが `workload-identity/sample_identity-*` のようなパターンだと不一致

**解決策**: IAMポリシーの workload-identity リソースをワイルドカードに拡張
```json
{
  "Sid": "BedrockAgentCoreIdentityGetResourceOauth2Token",
  "Effect": "Allow",
  "Action": ["bedrock-agentcore:GetResourceOauth2Token"],
  "Resource": [
    "arn:aws:bedrock-agentcore:REGION:ACCOUNT:token-vault/default",
    "arn:aws:bedrock-agentcore:REGION:ACCOUNT:token-vault/default/oauth2credentialprovider/*",
    "arn:aws:bedrock-agentcore:REGION:ACCOUNT:workload-identity-directory/default",
    "arn:aws:bedrock-agentcore:REGION:ACCOUNT:workload-identity-directory/default/workload-identity/*"
  ]
}
```

## AgentCore Identity 3LO: callback で authorizationCode/state が null エラー

**症状**: 3LO (USER_FEDERATION) フローで、ブラウザの Atlassian 同意後に callback endpoint でバリデーションエラー
```
{"message":"2 validation errors detected: Value at 'authorizationCode' failed to satisfy constraint: Member must not be null; Value at 'state' failed to satisfy constraint: Member must not be null"}
```

**原因**: `callback_url` に AgentCore の callback endpoint を直接指定していた。3LO フローは2段階で動作し、AgentCore callback → アプリの callback サーバーへのリダイレクトが必要。

**解決策**: アプリ側でローカル callback サーバーを立て、`callback_url` をそちらに向ける

```python
callback_url="http://localhost:9090/oauth2/callback"

identity_client.complete_resource_token_auth(
    session_uri=session_id,
    user_identifier=UserIdIdentifier(user_id="<user_id>"),
)
```

**追加設定**:
- Workload Identity の `allowedResourceOauth2ReturnUrls` に localhost URL を追加
- `fastapi` + `uvicorn` を依存関係に追加

**参考**: GitHub Issue #801、公式サンプル `05-Outbound_Auth_3lo/oauth2_callback_server.py`

## Bedrock: AccessDeniedException on inference-profile

**症状**: `AccessDeniedException: bedrock:InvokeModelWithResponseStream on resource: arn:aws:bedrock:*:*:inference-profile/*`

**原因**: クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する際、IAM権限が不足

**解決策**: IAMポリシーに`inference-profile/*`を追加
```typescript
resources: [
  'arn:aws:bedrock:*::foundation-model/*',
  'arn:aws:bedrock:*:*:inference-profile/*',  // 追加
]
```

## AgentCore Gateway Policy: ENFORCE モードが AWS_IAM で Internal Failure

**症状**: `authorizerType: AWS_IAM` のゲートウェイに Policy Engine を ENFORCE モードで関連付けると、`tools/list` / `tools/call` が以下のエラーで失敗する：
```
Tool Execution Denied: Policy Evaluation Internal Failure
```
LOG_ONLY モードでは正常にツール呼び出しが通過する。

**原因**: **Policy Engine の ENFORCE は `CUSTOM_JWT`（OAuth/Cognito）認証専用**。Cedar スキーマの Principal Type が `AgentCore::OAuthUser` 固定であり、JWT の `sub` クレームから principal を構築する設計。`AWS_IAM` 認証では principal エンティティを構築できず Internal Failure になる。

**解決策**: Policy Engine（特に ENFORCE モード）を使うには `CUSTOM_JWT` 認証のゲートウェイが必要

```python
# NG: AWS_IAM + ENFORCE → Internal Failure
agentcore.create_gateway(
    name="my-gateway",
    authorizerType="AWS_IAM",
    policyEngineConfiguration={"enforcementMode": "ENFORCE", ...},
)

# OK: CUSTOM_JWT + ENFORCE → 動作する
agentcore.create_gateway(
    name="my-gateway",
    authorizerType="CUSTOM_JWT",
    authorizerConfiguration={"usingJWT": {"discoveryUrl": "https://cognito-idp.../.well-known/openid-configuration", ...}},
    policyEngineConfiguration={"enforcementMode": "ENFORCE", ...},
)
```

**補足**:
- `authorizerType` は既存ゲートウェイでは変更不可（`update_gateway` で `ValidationException`）。新規作成が必要
- Cedar ポリシーで `principal.hasTag("department")` 等を使う場合、JWT トークンにカスタムクレームが必要

## AgentCore Observability: トレースが出力されない

**症状**: AgentCore Observability ダッシュボードでメトリクスが全て0、トレースが表示されない

**原因**: CDKでデプロイする場合、以下の4つすべてが必要（1つでも欠けるとトレースが出ない）

**解決策チェックリスト**:

1. **requirements.txt**
   - [x] `strands-agents[otel]` が含まれている（`strands-agents` だけではNG）
   - [x] `aws-opentelemetry-distro` が含まれている

2. **Dockerfile**
   - [x] CMD が `opentelemetry-instrument python agent.py` になっている
   ```dockerfile
   CMD ["opentelemetry-instrument", "python", "agent.py"]
   ```

3. **CDK環境変数**
   - [x] 以下の環境変数を設定
   ```typescript
   environmentVariables: {
     AGENT_OBSERVABILITY_ENABLED: 'true',
     OTEL_PYTHON_DISTRO: 'aws_distro',
     OTEL_PYTHON_CONFIGURATOR: 'aws_configurator',
     OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
   }
   ```

4. **import パス**（最重要！見落としやすい）
   - [x] `from bedrock_agentcore import BedrockAgentCoreApp` を使用
   - `from bedrock_agentcore.runtime import BedrockAgentCoreApp` だとトレースが出ない
   ```python
   # OK
   from bedrock_agentcore import BedrockAgentCoreApp
   # NG（トレースが出力されない）
   from bedrock_agentcore.runtime import BedrockAgentCoreApp
   ```

5. **CloudWatch Transaction Search**（アカウントごとに1回）
   ```bash
   aws xray get-trace-segment-destination --region us-east-1
   # Destination: CloudWatchLogs, Status: ACTIVE であること
   ```

6. **ログポリシー**（アカウントごとに1回）
   ```bash
   aws logs describe-resource-policies --region us-east-1
   # TransactionSearchXRayAccess ポリシーが存在すること
   ```

## S3 Vectors: Filterable metadata must have at most 2048 bytes

**症状**: Knowledge BaseのSync時にエラー `Filterable metadata must have at most 2048 bytes`

**原因**: S3 Vectorsではデフォルトで全メタデータがFilterable（2KB上限）扱い。

| メタデータタイプ | 上限 |
|-----------------|------|
| Filterable（フィルタリング可能） | **2KB** |
| Non-filterable（フィルタリング不可） | 40KB |

**解決策**: VectorIndex作成時に`MetadataConfiguration.NonFilterableMetadataKeys`を設定

```typescript
const vectorIndex = new CfnResource(stack, 'VectorIndex', {
  type: 'AWS::S3Vectors::Index',
  properties: {
    VectorBucketName: 'my-vectors-bucket',
    IndexName: 'my-index-v2',
    DataType: 'float32',
    Dimension: 1024,
    DistanceMetric: 'cosine',
    MetadataConfiguration: {
      NonFilterableMetadataKeys: [
        'AMAZON_BEDROCK_TEXT',
        'AMAZON_BEDROCK_METADATA',
      ],
    },
  },
});
```

**注意**: `MetadataConfiguration`の変更はReplacement（リソース再作成）を伴う。

## Amplify sandbox: amplify_outputs.json が見つからない

**症状**: `Cannot find module '../amplify_outputs.json'`

**原因**: sandbox が起動していない

**解決策**: `npx ampx sandbox` を実行

## Amplify Console: CDK failed to publish assets

**症状**: `[CDKAssetPublishError] CDK failed to publish assets`

**原因**: サービスロールの権限不足（デフォルトで作成される`AmplifySSRLoggingRole`はロギング専用）

**解決策**: 適切な権限を持つサービスロールを作成・設定

```bash
# 1. サービスロールを作成
aws iam create-role \
  --role-name AmplifyServiceRole-myapp \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "amplify.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# 2. AdministratorAccess-Amplifyポリシーをアタッチ
aws iam attach-role-policy \
  --role-name AmplifyServiceRole-myapp \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess-Amplify

# 3. Amplifyアプリに設定
aws amplify update-app \
  --app-id YOUR_APP_ID \
  --iam-service-role-arn arn:aws:iam::ACCOUNT_ID:role/AmplifyServiceRole-myapp
```

## Amplify Console: Dockerビルドができない

**症状**: `Unable to execute 'docker' in order to build a container asset`

**原因**: デフォルトビルドイメージにDockerが含まれていない

**解決策**: カスタムビルドイメージを設定

1. Amplify Console → Build settings → Build image settings → Edit
2. Build image → Custom Build Image を選択
3. イメージ名: `public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0`

## AgentCore WebSocket: JWT 認証が使えない

**症状**: ブラウザから AgentCore の WebSocket エンドポイントに接続できない（認証エラー）

**原因**: `RuntimeAuthorizerConfiguration.usingJWT()` で設定した JWT 認証は HTTP invocations 用。ブラウザの WebSocket API はカスタムヘッダーを設定できないため、JWT トークンを渡せない

**解決策**: JWT 認証を削除し、IAM (SigV4) 事前署名 URL + Cognito Identity Pool に変更

```typescript
// CDK: Identity Pool の認証済みロールに権限付与
authenticatedRole.addToPrincipalPolicy(new iam.PolicyStatement({
  actions: ['bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream'],
  resources: [runtime.agentRuntimeArn, `${runtime.agentRuntimeArn}/*`],
}));
```

```typescript
// ブラウザ: SigV4 presigned URL で WebSocket 接続
const signer = new SignatureV4({
  service: 'bedrock-agentcore', region, credentials, sha256: Sha256,
});
const presigned = await signer.presign(request, { expiresIn: 300 });
const ws = new WebSocket(`wss://...?${queryString}`);
```

## Dockerfile: PyAudio ビルド失敗（strands-agents[bidi]）

**症状**: Docker ビルド時に `strands-agents[bidi]` のインストールで PyAudio のビルドが失敗する

**原因**: Python slim イメージには C コンパイラと PortAudio ライブラリがない

**解決策**: `portaudio19-dev` + `build-essential` を追加

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    portaudio19-dev build-essential \
    && rm -rf /var/lib/apt/lists/*
```

## uv: AWS認証エラー

**症状**: `aws login`で認証したのにBoto3でエラー

**原因**: `botocore[crt]`が不足

**解決策**:
```bash
uv add 'botocore[crt]'
```

## デバッグTips

### CloudWatch Logs

Lambda/AgentCoreの問題を調査する際は、AWS CLIでログを確認：
```bash
aws logs tail /aws/bedrock-agentcore/runtime/RUNTIME_NAME --follow
```

### CloudWatch Logs Insights: タイムゾーン変換で時刻がズレる

**症状**: `datefloor(@timestamp + 9h, 1h)` でJSTに変換しているのに、結果の時刻がおかしい

**原因**: CloudWatch Logs Insightsの `datefloor(@timestamp + 9h, ...)` は挙動が不安定

**解決策**: UTCのまま集計してから、スクリプト側でJSTに変換する

```bash
# クエリはUTCで集計
--query-string 'stats count(*) by datefloor(@timestamp, 1h) as hour_utc | sort hour_utc asc'

# 結果をスクリプト側でJSTに変換
JST_HOUR=$(( (10#$UTC_HOUR + 9) % 24 ))
```

### AgentCore: OTELログ形式でinvocationがカウントできない

**症状**: `filter @message like /invocations/` でログをカウントしているが、件数が0になる

**原因**: OTEL有効時、ログ形式がJSON（OTEL形式）に変わり、従来のパターンマッチが効かない

**解決策**: `session.id` をparseしてユニークカウントする

```
# 旧方式（OTELログでは効かない）
filter @message like /invocations/ or @message like /POST/

# 新方式（OTEL対応）
parse @message /"session\.id":\s*"(?<sid>[^"]+)"/
| filter ispresent(sid)
| stats count_distinct(sid) as sessions
```
