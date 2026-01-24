# Bedrock AgentCore ナレッジ

Bedrock AgentCore Runtime に関する学びを記録する。

## 利用可能リージョン

- us-east-1（バージニア北部）
- us-west-2（オレゴン）

## JWT認証

### Cognito統合時のトークン選択

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

## IAM権限

### Bedrockモデル呼び出し権限

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

## SSEストリーミング

### エンドポイントURL形式

```
POST https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{URLエンコードARN}/invocations?qualifier={endpointName}
```

**重要**: ARNは `encodeURIComponent()` で完全にURLエンコードする必要がある。

### レスポンス形式

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

## 環境変数

### Runtimeへの環境変数渡し

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

または`dotenv`を使用：
```typescript
// amplify/backend.ts
import 'dotenv/config';
```

## CDK Hotswap

CDK v1.14.0 以降で AgentCore Runtime の Hotswap に対応。コンテナイメージの変更時に高速デプロイが可能。

### Amplify での利用

Amplify toolkit-lib がまだ対応バージョンに更新されていない場合、`package.json` の `overrides` で先行利用可能：

```json
{
  "overrides": {
    "@aws-cdk/toolkit-lib": "1.14.0",
    "@smithy/core": "^3.21.0"
  }
}
```

詳細は `amplify-cdk.md` を参照。

## CDK（@aws-cdk/aws-bedrock-agentcore-alpha）

### Runtime作成

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

const endpoint = runtime.addEndpoint('my-endpoint');
```

### Amplify Gen2統合

```typescript
// amplify/backend.ts
backend.addOutput({
  custom: {
    agentEndpointArn: endpoint.agentRuntimeEndpointArn,
  },
});
```
