# AgentCore CDK runtime patterns

## 目次

- AgentCore CDK
  - Runtime作成（推奨パターン）
  - JWT認証（Cognito統合）
    - DiscoveryUrl には `/.well-known/openid-configuration` が必須
    - allowedClients は client_id クレームを検証
  - IAM権限（Bedrockモデル呼び出し）
  - 環境変数渡し
  - **リクエストヘッダーは許可リストに入れないとコンテナへ届かない**（`Authorization` も既定では届かない）
  - DEFAULTエンドポイント
  - SSEストリーミング
  - JWT認証時はHTTPS直接呼び出し（SDK非対応）

## AgentCore CDK

### Runtime作成（推奨パターン）

```typescript
import * as agentcore from '@aws-cdk/aws-bedrock-agentcore-alpha';

const artifact = agentcore.AgentRuntimeArtifact.fromAsset(
  path.join(__dirname, 'runtime')
);

const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  authorizerConfiguration: agentcore.RuntimeAuthorizerConfiguration.usingJWT(
    discoveryUrl,
    [clientId],  // allowedClients - client_idクレームを検証
  ),
});

// エンドポイントはDEFAULTを使用（addEndpoint不要）
```

### JWT認証（Cognito統合）

#### DiscoveryUrl には `/.well-known/openid-configuration` が必須

AgentCore の `usingJWT` に渡す `discoveryUrl` は、末尾に `/.well-known/openid-configuration` を含める必要がある。issuer URL のみ（例: `https://cognito-idp.us-east-1.amazonaws.com/{userPoolId}`）を渡すとバリデーションエラーになる。

```typescript
// NG: issuer URL のみ -> CFn バリデーションエラー
const discoveryUrl = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}`;

// OK: フルパス
const discoveryUrl = `https://cognito-idp.${region}.amazonaws.com/${userPoolId}/.well-known/openid-configuration`;
```

**エラーメッセージ**: `DiscoveryUrl: string [...] does not match pattern ^.+/\.well-known/openid-configuration$`

#### allowedClients は client_id クレームを検証

AgentCore RuntimeのJWT認証（`usingJWT`の`allowedClients`）は **`client_id`クレーム** を検証する。

| トークン種別 | クライアントIDの格納先 | AgentCore認証 |
|-------------|---------------------|--------------|
| IDトークン | `aud` クレーム | NG |
| アクセストークン | `client_id` クレーム | OK |

**結論**: Cognito + AgentCore 連携では**アクセストークン**を使用する。

```typescript
// フロントエンドでの実装例
const session = await fetchAuthSession();
const accessToken = session.tokens?.accessToken?.toString();  // IDトークンではなくアクセストークン
```

### IAM権限（Bedrockモデル呼び出し）

クロスリージョン推論（`us.anthropic.claude-*`形式のモデルID）を使用する場合、以下の両方のリソースへの権限が必要：

```typescript
runtime.addToRolePolicy(new iam.PolicyStatement({
  actions: [
    'bedrock:InvokeModel',
    'bedrock:InvokeModelWithResponseStream',
  ],
  resources: [
    'arn:aws:bedrock:*::foundation-model/*',      // 基盤モデル
    'arn:aws:bedrock:*:*:inference-profile/*',    // 推論プロファイル（クロスリージョン推論）
  ],
}));
```

`foundation-model/*` だけでは `AccessDeniedException` が発生する。

### 環境変数渡し

環境変数にはログレベルや公開APIのベースURLなど、漏えいしても問題のない設定だけを渡す。

```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    LOG_LEVEL: process.env.LOG_LEVEL || 'INFO',
    API_BASE_URL: process.env.API_BASE_URL || 'https://api.example.com',
  },
});
```

APIキーやOAuthクレデンシャルはコード、`.env`の展開コマンド、CloudFormationプロパティへ埋め込まない。AgentCore Identityまたは承認済みのシークレット管理サービスから実行時に取得する。

### リクエストヘッダーは許可リストに入れないとコンテナへ届かない

**AgentCore Runtime は、既定でどのリクエストヘッダーもコンテナへ渡さない。`Authorization` も例外ではない。** JWTオーソライザーで検証しても、検証は AgentCore 側で完結し、トークンはエージェントコードへ届かない。渡したいヘッダーは `requestHeaderConfiguration.requestHeaderAllowlist` へ明示する。

```typescript
new agentcore.CfnRuntime(this, 'Runtime', {
  authorizerConfiguration: { customJwtAuthorizer: { discoveryUrl, allowedClients } },
  // これが無いと context.request_headers が空になる
  requestHeaderConfiguration: { requestHeaderAllowlist: ['Authorization'] },
  // ...
});
```

**エラーにならないのが厄介**で、`context.request_headers` が `None` になるだけ。利用者識別やテナント判定を JWT クレームから行っていると、**例外も警告も出ないまま統計だけが空になる**。

- **ローカル実行では再現しない。** `app.run()` で SDK が直接 HTTP を受けるときは許可リストの制御が効かないので、ヘッダーはそのまま届く。「ローカルで動いたから実装は正しい」は本番の根拠にならない。切り分けには、ローカルで受信ヘッダーのキー名を出す最小アプリを立てて本番のログと突き合わせる
- 署名の再検証は不要（AgentCore が検証済み）。`jwt.decode(token, options={"verify_signature": False})` でクレームだけ取り出す
- **設定が落ちたことを検知できるテストを1本置く。** CDK のソースに `requestHeaderAllowlist` と `'Authorization'` が含まれることを静的検査するだけでよい。壊れても無症状なので、テストが無いと次に気づくのは「統計を見ようとしたとき」になる

### DEFAULTエンドポイント

Runtime を作成すると **DEFAULT エンドポイントが自動的に作成される**。特別な理由がなければ `addEndpoint()` は不要。

```typescript
// NG: 不要なエンドポイントが増える
const endpoint = runtime.addEndpoint('my-endpoint');  // DEFAULT + my-endpoint の2つになる

// OK: DEFAULTエンドポイントを使う
// addEndpoint() を呼ばない -> DEFAULTのみ
```

### SSEストリーミング

エンドポイントURL形式：
```
POST https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{URLエンコードARN}/invocations?qualifier={endpointName}
```

**重要**: ARNは `encodeURIComponent()` で完全にURLエンコードする必要がある。

### JWT認証時はHTTPS直接呼び出し（SDK非対応）

customJWTAuthorizer が設定されたランタイムには、AWS SDK / CLI の `invoke_agent_runtime` が使えない（`Authorization method mismatch` エラー）。HTTPS エンドポイントに直接リクエストする：

```typescript
// フロントエンドでの呼び出し例
const session = await fetchAuthSession();
const token = session.tokens?.accessToken?.toString();
const region = AGENT_ARN.split(':')[3];
const url = `https://bedrock-agentcore.${region}.amazonaws.com/runtimes/${encodeURIComponent(AGENT_ARN)}/invocations?qualifier=DEFAULT`;

const res = await fetch(url, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    'X-Amzn-Bedrock-AgentCore-Runtime-Session-Id': sessionId,  // 33文字以上必須
  },
  body: JSON.stringify({ prompt: userText, session_id: sessionId }),
});
```

**制約**:
- `X-Amzn-Bedrock-AgentCore-Runtime-Session-Id` は33-256文字の制約あり（短いとバリデーションエラー）
- JWT使用時はIAM SigV4認証と**併用不可**（どちらか一方）

レスポンス形式：
```
data: {"type": "text", "data": "テキストチャンク"}
data: {"type": "tool_use", "data": "ツール名"}
data: {"type": "markdown", "data": "生成されたコンテンツ"}
data: {"type": "error", "error": "エラーメッセージ"}
data: [DONE]
```

イベントペイロードは `content` または `data` フィールドに格納される。両方に対応が必要：
```typescript
const textValue = event.content || event.data;
```

---
