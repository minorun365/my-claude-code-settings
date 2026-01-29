# Bedrock AgentCore ナレッジ

Bedrock AgentCore Runtime に関する学びを記録する。

## 利用可能リージョン

15リージョンで利用可能（2026年1月時点）。主要なもの：

- us-east-1（バージニア北部）
- us-west-2（オレゴン）
- ap-northeast-1（東京）
- その他: us-east-2, eu-central-1, eu-west-1/2/3, eu-north-1, ap-south-1, ap-southeast-1/2, ap-northeast-2, ca-central-1, sa-east-1

※Evaluations機能のみ一部リージョン限定（東京は非対応）

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

## エンドポイント管理

### DEFAULTエンドポイント

Runtime を作成すると **DEFAULT エンドポイントが自動的に作成される**。特別な理由がなければ `addEndpoint()` は不要。

```typescript
// NG: 不要なエンドポイントが増える
const endpoint = runtime.addEndpoint('my-endpoint');  // DEFAULT + my-endpoint の2つになる

// OK: DEFAULTエンドポイントを使う
// addEndpoint() を呼ばない → DEFAULTのみ
```

### フロントエンドからの呼び出し

DEFAULTエンドポイントを使用する場合：

```typescript
const runtimeArn = outputs.custom?.agentRuntimeArn;
const encodedArn = encodeURIComponent(runtimeArn);
const url = `https://bedrock-agentcore.${region}.amazonaws.com/runtimes/${encodedArn}/invocations?qualifier=DEFAULT`;
```

### 不要なエンドポイントの削除

```bash
aws bedrock-agentcore-control delete-agent-runtime-endpoint \
  --agent-runtime-id {runtimeId} \
  --endpoint-name {endpointName} \
  --region us-east-1
```

## Observability（トレース）

### 必要な設定

AgentCore Observability でトレースを出力するには、以下の設定が必要：

1. **requirements.txt に OTEL パッケージを追加**

```
strands-agents[otel]          # otel extra が必要
aws-opentelemetry-distro      # ADOT
```

2. **Dockerfileで `opentelemetry-instrument` を使って起動**

```dockerfile
# OTELの自動計装を有効にして起動
CMD ["opentelemetry-instrument", "python", "agent.py"]
```

**注意**: `python agent.py` だけではOTELトレースが出力されない。

3. **CDKで環境変数を設定**（CDKデプロイの場合に必要）

```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  // ...
  environmentVariables: {
    // Observability（OTEL）設定
    AGENT_OBSERVABILITY_ENABLED: 'true',
    OTEL_PYTHON_DISTRO: 'aws_distro',
    OTEL_PYTHON_CONFIGURATOR: 'aws_configurator',
    OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
  },
});
```

**注意**: `bedrock_agentcore_starter_toolkit` でデプロイすると自動設定されるが、CDKの場合は手動で環境変数が必要。

4. **CloudWatch Transaction Search を有効化**（アカウントごとに1回）

```bash
# ポリシー作成
aws logs put-resource-policy --policy-name TransactionSearchPolicy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "TransactionSearchXRayAccess",
    "Effect": "Allow",
    "Principal": {"Service": "xray.amazonaws.com"},
    "Action": "logs:PutLogEvents",
    "Resource": [
      "arn:aws:logs:us-east-1:*:log-group:aws/spans:*",
      "arn:aws:logs:us-east-1:*:log-group:/aws/application-signals/data:*"
    ]
  }]
}' --region us-east-1

# トレース送信先をCloudWatchに設定
aws xray update-trace-segment-destination --destination CloudWatchLogs --region us-east-1
```

### トレースの確認

1. CloudWatch Console → **Bedrock AgentCore GenAI Observability**
2. Agents View / Sessions View / Traces View で確認可能

### OTELログ形式

OTEL有効時、ログは `otel-rt-logs` ストリームにJSON形式で出力される。各セッションは `session.id` フィールドで識別される。

```json
{
  "resource": { ... },
  "scope": { "name": "strands.telemetry.tracer" },
  "timeUnixNano": 1769681571307833653,
  "body": {
    "input": { "messages": [...] },
    "output": { "messages": [...] }
  },
  "attributes": {
    "session.id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

### CloudWatch Logs Insightsでのセッションカウント

OTELログからセッション数をカウントするクエリ：

```
parse @message /"session\.id":\s*"(?<sid>[^"]+)"/
| filter ispresent(sid)
| stats count_distinct(sid) as sessions by datefloor(@timestamp, 1h) as hour_utc
| sort hour_utc asc
```

**注意**: `datefloor(@timestamp + 9h, ...)` を使うと挙動が不安定。UTCで集計してからスクリプト側でJSTに変換する。

```bash
# UTCの時刻をJSTに変換
JST_HOUR=$(( (10#$UTC_HOUR + 9) % 24 ))
```

## CDK（@aws-cdk/aws-bedrock-agentcore-alpha）

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

### Amplify Gen2統合

```typescript
// amplify/backend.ts
backend.addOutput({
  custom: {
    agentRuntimeArn: runtime.agentRuntimeArn,  // RuntimeのARNを出力
    environment: isSandbox ? 'sandbox' : branchName,
  },
});
```
