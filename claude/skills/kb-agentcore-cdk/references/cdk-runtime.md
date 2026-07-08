# AgentCore CDK runtime patterns

## 目次

- AgentCore CDK
  - Runtime作成（推奨パターン）
  - JWT認証（Cognito統合）
    - DiscoveryUrl には `/.well-known/openid-configuration` が必須
    - allowedClients は client_id クレームを検証
  - IAM権限（Bedrockモデル呼び出し）
  - 環境変数渡し
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

```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    TAVILY_API_KEY: process.env.TAVILY_API_KEY || '',
    OTHER_SECRET: process.env.OTHER_SECRET || '',
  },
});
```

sandbox起動時に環境変数を設定する必要がある：
```bash
export TAVILY_API_KEY=$(grep TAVILY_API_KEY .env | cut -d= -f2) && npx ampx sandbox
```

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
