---
name: kb-troubleshooting
description: トラブルシューティング集。AWS/フロントエンド/Python/LLMアプリの問題解決
user-invocable: true
---

# トラブルシューティング集

プロジェクト横断で遭遇した問題と解決策を記録する。

## AWS関連

### Cognito認証: client_id mismatch

**症状**: `Claim 'client_id' value mismatch with configuration.`

**原因**: IDトークンを使用していたが、APIがアクセストークンの`client_id`クレームを検証していた

**解決策**: アクセストークンを使用する
```typescript
// NG
const idToken = session.tokens?.idToken?.toString();

// OK
const accessToken = session.tokens?.accessToken?.toString();
```

### AgentCore JWT: DiscoveryUrl バリデーションエラー

**症状**: `Properties validation failed for resource ... DiscoveryUrl: string [...] does not match pattern ^.+/\.well-known/openid-configuration$`

**原因**: `usingJWT` の `discoveryUrl` に issuer URL のみを渡していた（末尾の `/.well-known/openid-configuration` が欠落）

**解決策**: フルパスで指定する
```typescript
// NG
`https://cognito-idp.${region}.amazonaws.com/${userPoolId}`

// OK
`https://cognito-idp.${region}.amazonaws.com/${userPoolId}/.well-known/openid-configuration`
```

### Bedrock Model Detector: 重複通知メール

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

**教訓**: 定期ポーリング型の差分検知では、外部APIの一時的な不安定性を考慮し、累積方式でデータを保持する。「消えたものを消す」ではなく「増えたものだけ追加する」設計が安全。

### CDK Lambda: ARM64バンドリングでImportModuleError

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

**教訓**: pydantic_core等のCコンパイル済みバイナリはアーキテクチャ不一致で即座にエラーになる。x86_64でビルドしたバイナリはARM64 Lambdaで動かない。

### AgentCore Identity: workload-identity ARN 不一致

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

### AgentCore Identity 3LO: callback で authorizationCode/state が null エラー

**症状**: 3LO (USER_FEDERATION) フローで、ブラウザの Atlassian 同意後に callback endpoint でバリデーションエラー
```
{"message":"2 validation errors detected: Value at 'authorizationCode' failed to satisfy constraint: Member must not be null; Value at 'state' failed to satisfy constraint: Member must not be null"}
```

**原因**: `callback_url` に AgentCore の callback endpoint（`https://bedrock-agentcore.REGION.amazonaws.com/identities/oauth2/callback/UUID`）を直接指定していた。3LO フローは2段階で動作し、AgentCore callback → アプリの callback サーバーへのリダイレクトが必要。AgentCore endpoint を callback_url に指定すると、自分自身にリダイレクトして `session_id` のみのリクエストを受け取り、code/state が null になる。

**解決策**: アプリ側でローカル callback サーバーを立て、`callback_url` をそちらに向ける

```python
# callback_url を localhost に変更
callback_url="http://localhost:9090/oauth2/callback"

# ローカル callback サーバーで CompleteResourceTokenAuth を呼ぶ
identity_client.complete_resource_token_auth(
    session_uri=session_id,
    user_identifier=UserIdIdentifier(user_id="<user_id>"),
)
```

**追加設定**:
- Workload Identity の `allowedResourceOauth2ReturnUrls` に localhost URL を追加
- `fastapi` + `uvicorn` を依存関係に追加

**参考**: GitHub Issue #801、公式サンプル `05-Outbound_Auth_3lo/oauth2_callback_server.py`

### Bedrock: AccessDeniedException on inference-profile

**症状**: `AccessDeniedException: bedrock:InvokeModelWithResponseStream on resource: arn:aws:bedrock:*:*:inference-profile/*`

**原因**: クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する際、IAM権限が不足

**解決策**: IAMポリシーに`inference-profile/*`を追加
```typescript
resources: [
  'arn:aws:bedrock:*::foundation-model/*',
  'arn:aws:bedrock:*:*:inference-profile/*',  // 追加
]
```

### AgentCore Gateway Policy: ENFORCE モードが AWS_IAM で Internal Failure

**症状**: `authorizerType: AWS_IAM` のゲートウェイに Policy Engine を ENFORCE モードで関連付けると、`tools/list` / `tools/call` が以下のエラーで失敗する：
```
Tool Execution Denied: Policy Evaluation Internal Failure
```
LOG_ONLY モードでは正常にツール呼び出しが通過する。

**原因**: **Policy Engine の ENFORCE は `CUSTOM_JWT`（OAuth/Cognito）認証専用**。Cedar スキーマの Principal Type が `AgentCore::OAuthUser` 固定であり、JWT の `sub` クレームから principal を構築する設計。`AWS_IAM` 認証では principal エンティティを構築できず Internal Failure になる。

根拠：
- Cedar スキーマ制約: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy-schema-constraints.html
- Authorization flow（JWT `sub` 由来）: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy-authorization-flow.html
- 公式の Gateway + Policy 作成例が `CUSTOM_JWT` のみ: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/create-gateway-with-policy.html
- AWS 公式サンプル4リポジトリで `AWS_IAM` + Policy Engine の例がゼロ

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
- LOG_ONLY が「動く」のは評価成功ではなく、評価失敗を飲み込んで通しているだけの可能性が高い
- Cedar ポリシーで `principal.hasTag("department")` 等を使う場合、JWT トークンにカスタムクレームが必要（Cognito 標準クレームだけでは不足）
- `amount` のスキーマ型 `number` は Cedar では Decimal にマッピングされる。`< 500` は Long 型のみ対応、Decimal は `.lessThan(decimal("500.0"))` を使う

### AgentCore Observability: トレースが出力されない

**症状**: AgentCore Observability ダッシュボードでメトリクスが全て0、トレースが表示されない

**原因**: CDKでデプロイする場合、以下の4つすべてが必要（1つでも欠けるとトレースが出ない）

**解決策チェックリスト**:

1. **requirements.txt**
   - [x] `strands-agents[otel]` が含まれている（`strands-agents` だけではNG）
   - [x] `aws-opentelemetry-distro` が含まれている

2. **Dockerfile**
   - [x] CMD が `opentelemetry-instrument python agent.py` になっている
   - `python agent.py` だけではOTELが有効にならない
   ```dockerfile
   CMD ["opentelemetry-instrument", "python", "agent.py"]
   ```

3. **CDK環境変数**（CDKデプロイの場合）
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
   - ログ・メトリクスは両パスで正常出力されるため、トレースだけ欠落していて気づきにくい
   ```python
   # OK
   from bedrock_agentcore import BedrockAgentCoreApp
   # NG（トレースが出力されない）
   from bedrock_agentcore.runtime import BedrockAgentCoreApp
   ```

5. **CloudWatch Transaction Search**（アカウントごとに1回）
   ```bash
   # 状態確認
   aws xray get-trace-segment-destination --region us-east-1
   # Destination: CloudWatchLogs, Status: ACTIVE であること
   ```

6. **ログポリシー**（アカウントごとに1回）
   ```bash
   aws logs describe-resource-policies --region us-east-1
   # TransactionSearchXRayAccess ポリシーが存在すること
   ```

**重要**: 1〜4はすべて必須。1つでも欠けるとトレースが出力されない。特に4番の import パスは、内部的に同じクラスが動くため見落としやすい。

### S3 Vectors: Filterable metadata must have at most 2048 bytes

**症状**: Knowledge BaseのSync時にエラー
```
Filterable metadata must have at most 2048 bytes
```

**原因**: S3 Vectorsではデフォルトで全メタデータがFilterable（2KB上限）扱い。Bedrock Knowledge Basesが使用する`AMAZON_BEDROCK_TEXT`（チャンク本文）と`AMAZON_BEDROCK_METADATA`がこの制限を超える。

| メタデータタイプ | 上限 |
|-----------------|------|
| Filterable（フィルタリング可能） | **2KB** |
| Non-filterable（フィルタリング不可） | 40KB |

**解決策**: VectorIndex作成時に`MetadataConfiguration.NonFilterableMetadataKeys`を設定

```typescript
// CDK (CfnResource)
const vectorIndex = new CfnResource(stack, 'VectorIndex', {
  type: 'AWS::S3Vectors::Index',
  properties: {
    VectorBucketName: 'my-vectors-bucket',
    IndexName: 'my-index-v2',  // ← v2にリネーム必要（後述）
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

**注意**: `MetadataConfiguration`の変更はCloudFormation的にReplacement（リソース再作成）を伴う。カスタム名のリソースは同名で再作成できないため：
1. 既存のKnowledge BaseとData Sourceを手動削除
2. IndexNameを変更（例: `my-index` → `my-index-v2`）
3. 再デプロイ

```bash
# 既存リソース削除
aws bedrock-agent delete-data-source --knowledge-base-id KB_ID --data-source-id DS_ID
aws bedrock-agent delete-knowledge-base --knowledge-base-id KB_ID
```

### Amplify sandbox: amplify_outputs.json が見つからない

**症状**: `Cannot find module '../amplify_outputs.json'`

**原因**: sandbox が起動していない

**解決策**: `npx ampx sandbox` を実行

### Amplify Console: CDK failed to publish assets

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

### Amplify Console: Dockerビルドができない

**症状**: `Unable to execute 'docker' in order to build a container asset`

**原因**: デフォルトビルドイメージにDockerが含まれていない

**解決策**: カスタムビルドイメージを設定

1. Amplify Console → Build settings → Build image settings → Edit
2. Build image → Custom Build Image を選択
3. イメージ名: `public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0`

### LINE Push Message: 429 月間メッセージ上限

**症状**: Push Message送信時に429エラー `{"message":"You have reached your monthly limit."}`

**原因**: 無料プラン（コミュニケーションプラン）の月200通上限に到達。SSEストリーミングで `contentBlockStop` ごとにPush Messageを送ると、1回の対話でツール通知+テキストブロック数だけ通数を消費する。

**解決策**: 最終テキストブロックのみ送信する方式に変更
- `contentBlockDelta` → バッファに蓄積
- `contentBlockStop` → `last_text_block` に保持（送信しない）
- ツール開始時 → バッファ破棄 + ステータスメッセージのみ送信
- SSE完了後 → `last_text_block` を1通だけ送信

**補足**: レート制限（2,000 req/s）とは別物。`Retry-After`ヘッダーは返されない。LINE公式は429を「リトライすべきでない4xx」に分類。

### LLM の曜日誤認識（strands_tools current_time）

**症状**: エージェントが日付の曜日を間違える（例: 月曜日を日曜日と回答）

**原因**: `strands_tools` の `current_time` は ISO 8601 形式（`2026-02-09T02:46:56+00:00`）を返すが、曜日情報が含まれない。LLM が自力で曜日を推測して間違える（LLM は日付→曜日の変換が苦手）

**解決策**: カスタムツールで JST＋曜日を直接返す

```python
JST = timezone(timedelta(hours=9))
WEEKDAY_JA = ["月", "火", "水", "木", "金", "土", "日"]

@tool
def current_time() -> str:
    now = datetime.now(JST)
    weekday = WEEKDAY_JA[now.weekday()]
    return f"{now.year}年{now.month}月{now.day}日({weekday}) {now.strftime('%H:%M')} JST"
```

**教訓**: LLM に計算させず、ツール側で確定した情報を返す。タイムゾーン変換もシステムプロンプト指示ではなくツール側で完結させる。

### AgentCore WebSocket: JWT 認証が使えない

**症状**: ブラウザから AgentCore の WebSocket エンドポイントに接続できない（認証エラー）

**原因**: `RuntimeAuthorizerConfiguration.usingJWT()` で設定した JWT 認証は HTTP invocations 用。ブラウザの WebSocket API はカスタムヘッダー（`Authorization: Bearer ...`）を設定できないため、JWT トークンを渡せない

**解決策**: JWT 認証を削除し、IAM (SigV4) 事前署名 URL + Cognito Identity Pool に変更

```typescript
// CDK: JWT認証を削除し、Identity Pool の認証済みロールに権限付与
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

### BidiNovaSonicModel: 音声が早送り/遅再生になる

**症状**: Nova Sonic の音声出力が早送り（1.5倍速）のように聞こえる

**原因**: `provider_config["audio"]` のキー名が間違っている。SDK は `input_rate` / `output_rate` を期待するが、`input_sample_rate` / `output_sample_rate` と書くと**無視され、デフォルトの 16kHz** が使われる。フロントエンドが 24kHz で再生すると 1.5 倍速になる

**解決策**: 正しいキー名を使う

```python
# ❌ NG: SDK が認識しないキー名（デフォルト 16kHz が使われる）
provider_config={
    "audio": {
        "input_sample_rate": 16000,
        "output_sample_rate": 24000,
    },
}

# ✅ OK: SDK が認識するキー名
provider_config={
    "audio": {
        "input_rate": 16000,
        "output_rate": 24000,
    },
}
```

**フロントエンド側**: `AudioBuffer` の `sampleRate` を `output_rate` と一致させる
```typescript
const SOURCE_SAMPLE_RATE = 24000; // backend の output_rate と一致
const audioBuffer = ctx.createBuffer(1, int16Data.length, SOURCE_SAMPLE_RATE);
```

**教訓**: Strands SDK の `_resolve_provider_config` は dict merge するだけなので、未知のキーはエラーにならず静かに無視される。音声速度がおかしい場合はまずキー名を確認する

### Dockerfile: PyAudio ビルド失敗（strands-agents[bidi]）

**症状**: Docker ビルド時に `strands-agents[bidi]` のインストールで PyAudio のビルドが失敗する

**原因**: Python slim イメージには C コンパイラと PortAudio ライブラリがない。`[bidi]` extra が PyAudio を依存に含む

**解決策**: `portaudio19-dev` + `build-essential` を追加

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    portaudio19-dev build-essential \
    && rm -rf /var/lib/apt/lists/*
```

**補足**: コンテナ内で WebSocket I/O を使う場合は PyAudio 自体は不要だが、`[bidi]` extra の依存として必要。

## フロントエンド関連

### Web Audio API: AudioContext({ sampleRate: 16000 }) が macOS で不安定

**症状**: `new AudioContext({ sampleRate: 16000 })` で作成した AudioContext で音声再生が不安定（ノイズ、途切れ、無音）

**原因**: macOS のオーディオハードウェアは通常 48kHz で動作する。16kHz を強制するとドライバレベルで不安定になる

**解決策**: AudioContext はネイティブサンプルレートで作成し、`createBuffer(1, length, 16000)` でソースの sampleRate を指定する

```typescript
// NG: sampleRate を 16kHz に強制
const ctx = new AudioContext({ sampleRate: 16000 });

// OK: ネイティブサンプルレート + AudioBuffer で 16kHz を指定
const ctx = new AudioContext(); // ネイティブ（通常 48kHz）
const buffer = ctx.createBuffer(1, data.length, 16000); // 16kHz として解釈
// Web Audio API が自動でリサンプリング（16kHz → 48kHz）
```

### Web Audio API: ブラウザで音が出ない（自動再生ポリシー）

**症状**: AudioBufferSourceNode で音声を再生しようとしても無音

**原因**: ブラウザの自動再生ポリシーにより、ユーザーインタラクションなしでは AudioContext が `suspended` 状態になる

**解決策**: ユーザーのボタンクリック等のタイミングで `AudioContext.resume()` を呼ぶ

```typescript
// ボタンクリックハンドラ内
const handleStartCall = async () => {
  await audioContext.resume(); // 必須！これがないと音が出ない
  // ... WebSocket接続等
};
```

### Nova Sonic トランスクリプト: 吹き出しが重複表示

**症状**: アシスタントの応答が吹き出しで2回表示される

**原因**: `isFinal=false` のときだけ直前エントリを上書きしていたため、`isFinal=true` が来ると新しいエントリとして追加され、同じ応答が2つ表示された

**解決策**: `isFinal` の値に関わらず、直前エントリが同じロールで `isFinal=false` なら上書き

```typescript
setTranscripts(prev => {
  const last = prev[prev.length - 1];
  if (last && last.role === role && !last.isFinal) {
    return [...prev.slice(0, -1), { role, text, isFinal }];
  }
  return [...prev, { role, text, isFinal }];
});
```

### Tailwind CSS v4: dev サーバーでユーティリティクラスが生成されない

**症状**: `npx vite` の dev サーバーで Tailwind のユーティリティクラス（`text-white`, `font-bold` 等）が一切生成されない。ビルド（`npx vite build`）では正常に動作する

**診断方法**: ブラウザの DevTools で CSS を確認
- 正常: 先頭が `/*! tailwindcss v4.x.x | MIT License */`、ユーティリティクラスが含まれる
- 異常: 先頭が `@layer theme, base, components, utilities;`、`@tailwind utilities` が未展開のまま残る

**原因**: `@tailwindcss/vite` プラグインの `transform` ハンドラー（`@tailwindcss/vite:generate:serve`）が Vite 7 の dev サーバーモードで呼ばれない場合がある。プラグインは正しく登録されるが、CSS ファイルに対して transform フックが実行されない。正確な発生条件は不明（同じバージョンの別プロジェクトでは正常に動作する）

**解決策**: `@tailwindcss/postcss`（PostCSS 方式）に切り替える

```javascript
// postcss.config.js（新規作成）
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

```typescript
// vite.config.ts から @tailwindcss/vite を削除
export default defineConfig({
  plugins: [react()],  // tailwindcss() を削除
})
```

```bash
npm install -D @tailwindcss/postcss
```

**なぜ PostCSS で解決するか**: PostCSS は Vite 組み込みの CSS 処理パイプライン（`vite:css` プラグイン）内で動作するため、プラグインの transform フック問題を完全に迂回できる。性能差もほぼない。

**効果がなかった対策**:
- node_modules クリーンインストール
- Vite キャッシュ削除（`rm -rf node_modules/.vite`）
- git init + コミット（Tailwind v4 の自動コンテンツ検出用）
- `@source "../src"` 追加（明示的スキャンパス指定）
- vite.config.ts を正常プロジェクトと完全同一にする
- node_modules 内のプラグインから transform.filter を削除

### OGP/Twitterカード: 画像が表示されない

**症状**: TwitterでURLをシェアしてもカード画像が表示されない

**原因**: 複数の設定が組み合わさって問題が発生。以下をすべて満たす必要がある。

**解決策チェックリスト**:

1. **metaタグ（必須）**
   - [x] `og:image` は絶対URL（`https://`から始まる）
   - [x] `og:url` でサイトURLを明示
   - [x] `og:image:secure_url` を追加
   - [x] `og:image:width` / `og:image:height` を追加
   - [x] `og:image:type` を追加（`image/jpeg` など）

2. **Twitter専用タグ（必須）**
   - [x] `twitter:card` は `summary`（小）か `summary_large_image`（大）
   - [x] `twitter:image` を明示的に指定
   - [x] `twitter:title` を明示的に指定
   - [x] `twitter:description` を明示的に指定

3. **画像ファイル**
   - [x] 5MB以下
   - [x] `summary` なら正方形（512x512推奨）
   - [x] `summary_large_image` なら横長（1200x630推奨）
   - [x] Exifメタデータを削除（iPhoneで撮った画像は要注意）
   - [x] HTTPSで配信されている

4. **キャッシュ対策**
   - [x] 画像URLにバージョンパラメータ追加（`?v=2` など）
   - [x] [Twitter Card Validator](https://cards-dev.twitter.com/validator) で再検証

**注意**: Twitterカードのキャッシュは最大7日間保持される。修正後すぐに反映されない場合がある。

### React StrictMode: 文字がダブって表示される

**症状**: ストリーミングUIで文字が2回表示される

**原因**: StrictModeで2回実行される際、シャローコピーしたオブジェクトを直接変更していた

**解決策**: イミュータブルな更新を使用
```typescript
// NG
setMessages(prev => {
  const newArr = [...prev];
  newArr[newArr.length - 1].content += chunk;
  return newArr;
});

// OK
setMessages(prev =>
  prev.map((msg, idx) =>
    idx === prev.length - 1 ? { ...msg, content: msg.content + chunk } : msg
  )
);
```

### Marp関連

Marp関連のトラブルシューティングは `/kb-marp` スキルを参照してください。

### SSE: チャットの吹き出しが空のまま

**症状**: APIは成功（200）だが、UIに内容が表示されない

**原因**: APIは`event.data`を返すが、コードは`event.content`を期待していた

**解決策**: 両方に対応
```typescript
const textValue = event.content || event.data;
```

### 疑似ストリーミング: エラーメッセージが表示されない

**症状**: `onError`コールバックで疑似ストリーミングを開始しても、メッセージが表示されない

**原因**: `onError`内の非同期関数が`await`されずに呼ばれ、`finally`ブロックが先に実行される。`finally`で`isStreaming: false`に設定されるため、ストリーミングループ内の`isStreaming`チェックが失敗する。

```typescript
// 問題のあるコード
onError: (error) => {
  streamErrorMessage(displayMessage);  // 非同期だがawaitされない
},
// ...
finally {
  // streamErrorMessageより先に実行される
  setMessages(prev =>
    prev.map(msg => msg.isStreaming ? { ...msg, isStreaming: false } : msg)
  );
}

// streamErrorMessage内
for (const char of message) {
  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.isStreaming  // ← false になっている
        ? { ...msg, content: msg.content + char }
        : msg
    )
  );
}
```

**解決策**: 疑似ストリーミングのループ内で`isStreaming`チェックを緩和する

```typescript
// NG: isStreamingをチェック（finallyで先にfalseになる）
idx === prev.length - 1 && msg.role === 'assistant' && msg.isStreaming

// OK: isStreamingチェックを削除
idx === prev.length - 1 && msg.role === 'assistant'
```

## Python関連

### uv: AWS認証エラー

**症状**: `aws login`で認証したのにBoto3でエラー

**原因**: `botocore[crt]`が不足

**解決策**:
```bash
uv add 'botocore[crt]'
```

### Marp CLI関連

Marp CLI関連のトラブルシューティング（PDF出力エラー、日本語文字化け、テーマ設定等）は `/kb-marp` スキルを参照してください。

## SNS連携関連

### Twitter/Xシェア: ツイートボックスにテキストが入力されない

**症状**: シェアリンクをクリックしてTwitterを開いても、ツイートボックスにテキストが何も入力されていない

**原因**: `https://x.com/compose/post?text=...` 形式を使用していた。この形式はXのWeb UI直接アクセス用で、`text`パラメータが無視されることがある

**解決策**: Twitter Web Intent形式を使用する

```python
# NG: compose/post形式（textパラメータが無視される）
url = f"https://x.com/compose/post?text={encoded_text}"

# OK: Web Intent形式（textパラメータが確実に反映される）
url = f"https://twitter.com/intent/tweet?text={encoded_text}"
```

## LLMアプリ関連

### ストリーミング中のコードブロック除去が困難

**症状**: LLMがマークダウンをテキストとして出力すると、チャンク単位で```の検出が難しい

**原因**: SSEイベントはチャンク単位で来るため、```markdown と閉じの ``` が別チャンクになる

**解決策**: 出力専用のツールを作成し、ツール経由で出力させる
```python
@tool
def output_content(content: str) -> str:
    """生成したコンテンツを出力します。"""
    global _generated_content
    _generated_content = content
    return "出力完了"
```

システムプロンプトで「必ずこのツールを使って出力してください」と指示する。

### Tavily APIキーの環境変数

**症状**: AgentCore RuntimeでTavily検索が動かない

**原因**: 環境変数がランタイムに渡されていない

**解決策**: CDKで環境変数を設定
```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    TAVILY_API_KEY: process.env.TAVILY_API_KEY || '',
  },
});
```

sandbox起動時に環境変数を設定:
```bash
export TAVILY_API_KEY=$(grep TAVILY_API_KEY .env | cut -d= -f2) && npx ampx sandbox
```

### Tavily APIレートリミット: フォールバックが効かない

**症状**: 複数APIキーのフォールバックを実装したが、枯渇したキーで止まり次のキーに切り替わらない

**原因**: Tavilyのエラーメッセージが `"This request exceeds your plan's set usage limit"` で、`rate limit` や `quota` という文字列を含まない

**解決策**: エラー判定条件に `"usage limit"` を追加
```python
if "rate limit" in error_str or "429" in error_str or "quota" in error_str or "usage limit" in error_str:
    continue  # 次のキーで再試行
```

## Amplify sandbox関連

### 複数sandboxインスタンス競合

**症状**:
```
[ERROR] [MultipleSandboxInstancesError] Multiple sandbox instances detected.
```

**原因**: 複数のampxプロセスが同時実行中

**解決策**:
```bash
# 1. プロセス確認
ps aux | grep "ampx" | grep -v grep

# 2. アーティファクトクリア
rm -rf .amplify/artifacts/

# 3. sandbox完全削除（正しい方法）
npx ampx sandbox delete --yes

# 4. 新しくsandbox起動
npx ampx sandbox
```

**注意**: `pkill` や `kill` でプロセスを強制終了すると状態が不整合になる。必ず `sandbox delete` を使う。

### sandbox変更が反映されない

**症状**: agent.pyを変更してもランタイムに反映されない

**原因候補**:
1. 複数sandboxインスタンスの競合
2. Docker未起動
3. Hotswapが正しく動作していない

**解決策**:
1. sandbox deleteで完全削除
2. Dockerが起動していることを確認
3. 新しくsandbox起動
4. デプロイ完了を待つ（5-10分）

### Docker未起動エラー（よくやる！）

**症状**:
```
ERROR: Cannot connect to the Docker daemon at unix:///Users/mi-onda/.docker/run/docker.sock. Is the docker daemon running?
[ERROR] [UnknownFault] ToolkitError: Failed to build asset
```

**原因**: Docker Desktopが起動していない（よく忘れる！）

**解決策**:
1. Docker Desktopを起動
2. sandboxを再起動、またはファイルをtouchして再トリガー

**予防策**: `npx ampx sandbox` を実行する前に Docker Desktop を起動する習慣をつける。または、ターミナルの起動時にDocker Desktopを自動起動するよう設定する

### Runtime名バリデーションエラー

**症状**:
```
[ValidationError] Runtime name must start with a letter and contain only letters, numbers, and underscores
```

**原因**: sandbox識別子（デフォルトでユーザー名）にハイフン等の禁止文字が含まれている（例: `mi-onda`）

**解決策**: `backend.ts`でRuntime名をサニタイズする

```typescript
// amplify/backend.ts
const backendName = agentCoreStack.node.tryGetContext('amplify-backend-name') as string;
// Runtime名に使えない文字をサニタイズ
nameSuffix = (backendName || 'dev').replace(/[^a-zA-Z0-9_]/g, '_');
// 結果: mi-onda → mi_onda
```

**ポイント**: 本番環境（AWS_BRANCH）でも同様のサニタイズを行う。ブランチ名に`/`や`-`が含まれる場合がある

### CDK DynamoDB: pointInTimeRecoverySpecificationの型エラー

**症状**:
```
Type 'boolean' is not assignable to type 'PointInTimeRecoverySpecification'.
```

**原因**: aws-cdk-libの最新版で`pointInTimeRecoverySpecification`の型が`boolean`から`PointInTimeRecoverySpecification`オブジェクト型に変更された

**解決策**: PITRが不要なら、プロパティ自体を削除する（デフォルトで無効）

```typescript
// NG: 古い書き方
const table = new dynamodb.Table(stack, 'MyTable', {
  partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
  pointInTimeRecoverySpecification: false,  // TypeScriptエラー
});

// OK: プロパティを削除（デフォルトでPITR無効）
const table = new dynamodb.Table(stack, 'MyTable', {
  partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
  // pointInTimeRecoverySpecification は指定しない
});
```

### S3バケット名: アンダースコア不可

**症状**:
```
[ValidationError] Invalid S3 bucket name (value: estimate-agent-data-mi_onda)
Bucket name must only contain lowercase characters and the symbols, period (.) and dash (-)
```

**原因**: S3バケット名にはアンダースコア（`_`）が使用不可。sandbox識別子がユーザー名（例: `mi_onda`）の場合に発生

**解決策**: バケット名生成時にアンダースコアをハイフンに変換

```typescript
// amplify/data/resource.ts
const sanitizedSuffix = nameSuffix.replace(/_/g, '-').toLowerCase();
const dataBucket = new s3.Bucket(stack, 'DataBucket', {
  bucketName: `my-bucket-${sanitizedSuffix}`,  // mi-onda になる
});
```

**S3バケット命名規則**:
- 小文字のみ（a-z）
- 数字（0-9）
- ハイフン（`-`）
- ピリオド（`.`）※ドメイン形式の場合

**使用不可**: アンダースコア（`_`）、大文字、スペース、その他の記号

### CSSショートハンド: list-style が list-style-position を上書きする

**症状**: テーマCSSで `list-style-position: inside` を指定しても効かない。computed style では `outside` のまま

**原因**: グローバルCSS（Tailwindリセット対策等）で `list-style: disc !important` を指定していた。`list-style` はショートハンドプロパティで、`list-style-type`、`list-style-position`、`list-style-image` を一括設定する。未指定のサブプロパティは `initial` にリセットされるため、`list-style-position` が暗黙的に `outside`（= initial）に `!important` 付きで上書きされていた

**解決策**: ショートハンドではなく個別プロパティで指定する

```css
/* NG: ショートハンドが list-style-position も上書きする */
.marpit ul { list-style: disc !important; }

/* OK: type のみ指定（position を上書きしない） */
.marpit ul { list-style-type: disc !important; }
```

**同様の落とし穴があるショートハンド**:
| ショートハンド | リセットされるサブプロパティ |
|-------------|------------------------|
| `list-style` | `list-style-type`, `list-style-position`, `list-style-image` |
| `background` | `background-image`, `background-position`, `background-size` 等 |
| `font` | `font-size`, `font-weight`, `line-height` 等 |
| `border` | `border-width`, `border-style`, `border-color` |

**教訓**: `!important` 付きのCSSルールでは特にショートハンドに注意。意図しないサブプロパティのリセットがテーマ固有のスタイルを壊す

### Tailwind: レスポンシブクラス変更がPC表示に反映されない

**症状**: `text-[8px]` に変更しても、PC画面で文字サイズが変わらない

**原因**: `md:text-xs` などのレスポンシブクラスがPC表示で優先されるため、ベースクラスの変更だけでは反映されない

**解決策**: ベースクラスとレスポンシブクラスの両方を変更する
```tsx
// NG: ベースのみ変更 → PCではmd:text-xsが適用される
className="text-[8px] md:text-xs"

// OK: 両方変更
className="text-[8px] md:text-[10px]"
```

### Amplify Console: SCP拒否エラー（Projectタグ必須環境）

**症状**:
```
lambda:CreateFunction ... with an explicit deny in a service control policy
```
Amplify自動生成のLambda（`AmplifyBranchLinkerCustomResourceLambda`等）でSCP拒否

**原因**: スタック単位でタグを付けても、Amplify内部で生成されるLambdaにはタグが付かない

**解決策**: **CDK Appレベル**でタグを付与

```typescript
// backend.ts
const app = cdk.App.of(agentCoreStack);
if (app) {
  cdk.Tags.of(app).add('Project', 'your-project-tag');
}
```

**NG（スタック単位）**:
```typescript
// これだとAmplify自動生成リソースにタグが付かない
cdk.Tags.of(agentCoreStack).add('Project', 'presales');
cdk.Tags.of(backend.auth.stack).add('Project', 'presales');
```

### Amplify カスタムドメイン: 所有権検証が通らない（PENDING_VERIFICATION）

**症状**: `create-domain-association` でカスタムドメインを追加したが、`PENDING_VERIFICATION` のまま何十分待っても `AVAILABLE` にならない

**原因**: サブドメインのDNSレコードをAレコード（Alias）で設定していた。Amplifyの所有権検証は **CNAMEレコード** を要求する

**解決策**: AレコードをCNAMEレコードに変更する

```bash
# NG: Aレコード（Alias）→ 検証が通らない
"Type": "A",
"AliasTarget": { "DNSName": "dXXXXXX.cloudfront.net" }

# OK: CNAMEレコード → 即座に検証通過
"Type": "CNAME",
"TTL": 300,
"ResourceRecords": [{"Value": "dXXXXXX.cloudfront.net"}]
```

**教訓**: CloudFrontへのルーティングでは通常Aレコード（Alias）が推奨だが、Amplifyのドメイン検証ではCNAMEが必須。

### Amplify defineFunction: @aws-sdk モジュール解決エラー

**症状**:
```
✘ [ERROR] Could not resolve "@aws-sdk/client-cognito-identity-provider"
```
Amplifyビルド（`npx ampx pipeline-deploy`）でesbuildがSDKモジュールを解決できない

**原因**: Amplify Gen2の`defineFunction`はAWS SDKパッケージを自動でexternalにしない。Lambda実行時にはSDKが利用可能だが、ビルド時にnode_modulesに存在しないとesbuildがエラーを出す

**解決策**: 必要なSDKパッケージを明示的にインストール
```bash
npm install @aws-sdk/client-cognito-identity-provider @aws-sdk/client-sts
```

### Cognito Migration Trigger: Lambdaが発火しない

**症状**: Migration Lambdaが設定済みだが、既存ユーザーのサインイン時にLambdaが発火しない（CloudWatch Logsにロググループすら作成されない）

**原因**: Amplify UIの`<Authenticator>`はデフォルトで`USER_SRP_AUTH`を使用。SRPではパスワードが暗号化されてCognitoに送信されるため、Migration TriggerにパスワードがlMlambdaに渡されず発火しない

**解決策**: Authenticatorの`services` propで`USER_PASSWORD_AUTH`フローを使うようオーバーライド

```tsx
import { signIn } from 'aws-amplify/auth';

<Authenticator
  services={{
    handleSignIn: (input) => signIn({
      ...input,
      options: { authFlowType: 'USER_PASSWORD_AUTH' }
    }),
  }}
>
```

**注意**: `USER_PASSWORD_AUTH`はパスワードを平文で送信する。移行完了後は`services`オーバーライドを削除してデフォルトのSRPに戻すこと

### dotenv: .env.local が読み込まれない

**症状**: `.env.local`に環境変数を設定したが、Node.js（Amplify CDK等）で読み込まれない

**原因**: `dotenv`パッケージはデフォルトで`.env`のみ読む。`.env.local`はVite/Next.jsの独自サポート

**解決策**: `.env.local` → `.env` にリネーム（Viteは`.env`も読むため互換性あり）

### AgentCore S3バケット: grantRead だけでは書き込み不可

**症状**: ツールでS3にファイルをアップロードしようとすると「AccessDenied」エラー

**原因**: CDKで `bucket.grantRead(runtime)` のみ設定していた

**解決策**: 書き込みが必要な場合は `grantReadWrite` を使用

```typescript
// NG: 読み取りのみ
uploadBucket.grantRead(runtime);

// OK: 読み書き
uploadBucket.grantReadWrite(runtime);
```

### Dockerfile: GitHubからフォントダウンロード失敗

**症状**: Dockerビルド中にcurlやwgetでGitHubからファイルをダウンロードするとエラー（exit code 8）

**原因**: GitHubのraw URLはリダイレクトする。wgetはデフォルトでリダイレクトを追従しない

**解決策**:
1. curlを使う場合は `-L` オプション必須
2. **最も確実**: フォントファイルをプロジェクトに含めてCOPYする

```dockerfile
# NG: wgetでリダイレクトを追従しない
RUN wget -q -O /app/fonts/font.ttf "https://github.com/..."

# OK: curlで-Lオプション
RUN curl -sL -o /app/fonts/font.ttf "https://github.com/..."

# 最も確実: プロジェクトに含めてCOPY
COPY fonts/ /app/fonts/
```

### AgentCore: CDKデプロイ後も環境変数・コードが反映されない

**症状**: CDKデプロイ後にAgentCoreのコード変更やデバッグログが反映されない、環境変数が古いまま

**原因**: AgentCore Runtimeはセッション単位でコンテナをキャッシュする。CDKデプロイしても既存の実行中コンテナは古いコード＆環境変数のまま動き続ける

**解決策**: `stop-runtime-session` で既存セッションを停止してから再テスト

```bash
aws bedrock-agentcore stop-runtime-session \
  --runtime-session-id "セッションID" \
  --agent-runtime-arn "arn:aws:bedrock-agentcore:REGION:ACCOUNT:runtime/RUNTIME_NAME" \
  --qualifier DEFAULT \
  --region REGION
```

**教訓**: AgentCoreのコード・環境変数を変更した場合は、必ず対象セッションを停止してからテストする。デプロイ完了 ≠ 既存コンテナへの反映。

### SSEエクスポート: 大きいファイルのダウンロードが失敗する（PPTX/PDF）

**症状**: スライドのPPTXダウンロードで「PPTX生成に失敗しました」エラー。URL共有（HTML生成）は成功する

**ブラウザコンソール**:
```
Download error: Error: PPTX生成に失敗しました
```

**原因**: SSEコネクションのアイドルタイムアウト。バックエンドでMarp CLI（Chromium）がPPTX変換中（数十秒〜120秒）、SSEストリームにデータが一切流れない。不安定なネットワーク（会場Wi-Fi等）ではこのアイドル期間にTCPコネクションがドロップし、`reader.read()` が `done: true` を返す。結果として `resultBlob` が null のまま関数が終了する

**CloudWatch Logsの落とし穴**: エクスポート処理に `print()` がないとログが0件になり、「リクエストが到達していない」と誤診しやすい

**解決策**: 3層の対策
1. **バックエンドにSSE keep-alive**（最も効果的）: 同期的なファイル変換処理を `asyncio.run_in_executor` でスレッド実行し、5秒ごとに `{"type": "progress"}` イベントをyield
2. **フロントエンドにリトライ**: 失敗時に1秒待って自動再試行（計2回）
3. **バックエンドにログ追加**: エクスポート処理の開始・完了・失敗を `print()` で記録

```python
# バックエンド: keep-aliveヘルパー
async def _wait_with_keepalive(task, format_name):
    while not task.done():
        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=5.0)
        except asyncio.TimeoutError:
            yield {"type": "progress", "message": f"{format_name}変換中..."}

# 使い方
loop = asyncio.get_event_loop()
task = loop.run_in_executor(None, generate_pptx, markdown, theme)
async for event in _wait_with_keepalive(task, "PPTX"):
    yield event  # SSEでkeep-aliveを送信
result = task.result()
```

```typescript
// フロントエンド: リトライ
for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
  try {
    return await _exportSlideOnce(markdown, format, theme);
  } catch (e) {
    if (attempt < MAX_RETRIES) {
      await new Promise(r => setTimeout(r, 1000));
    }
  }
}
```

**教訓**:
- SSEで長時間処理を返す場合、処理中もkeep-aliveイベントを送信してコネクションを維持する
- `share_slide`（HTML生成=軽い）が成功して`export_pptx`（PPTX変換=重い）が失敗する場合、処理時間の差がアイドルタイムアウトの原因
- バックエンドの全アクションに `print()` ログを入れておかないと、CloudWatch Logsで問題の切り分けができない

## デバッグTips

### Chrome DevTools MCP

ブラウザの問題を調査する際は、Chrome DevTools MCPを使用：
1. `list_console_messages` - コンソールエラー確認
2. `list_network_requests` - API呼び出し確認
3. `get_network_request` - リクエスト/レスポンス詳細確認

### CloudWatch Logs

Lambda/AgentCoreの問題を調査する際は、AWS CLIでログを確認：
```bash
aws logs tail /aws/bedrock-agentcore/runtime/RUNTIME_NAME --follow
```

### CloudWatch Logs Insights: タイムゾーン変換で時刻がズレる

**症状**: `datefloor(@timestamp + 9h, 1h)` でJSTに変換しているのに、結果の時刻がおかしい（古い時刻が返る）

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

### Marpテーマ確認

Marp関連のデバッグは `/kb-marp` スキルを参照してください。
