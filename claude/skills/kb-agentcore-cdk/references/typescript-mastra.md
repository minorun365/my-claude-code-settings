# TypeScript and Mastra container deployment

## 目次

- TypeScript エージェントのコンテナデプロイ（Mastra等）
  - 必要な依存関係（Mastra 構成）
  - 最小限の agent.ts
  - 動作する Dockerfile（マルチステージ）
  - tsconfig.json（ESM 必須設定）
  - ハマりポイント一覧
    - useradd -u 1000 でビルド失敗
    - agentcore dev は AWS_REGION を渡さない
    - @ai-sdk/amazon-bedrock のクレデンシャル問題
    - モデル ID のプレフィックスと AWS_REGION は揃える
    - bedrock-agentcore@0.2.3 のエラーが不透明な 500 になる
    - リクエストキーは prompt 固定
    - agentcore.json に Python のプレースホルダが残る（Container では無視）
    - agentcore deploy のコンテナビルドは CodeBuild ARM64
  - デバッグの基本動作（TypeScript Container）
- 関連スキル

## TypeScript エージェントのコンテナデプロイ（Mastra等）

agentcore CLI の公式チュートリアルは Python / Strands 前提。TypeScript + Mastra でコンテナデプロイする場合の固有ハマりポイントをまとめる。（CLI 全般は上記「AgentCore CLI」セクション参照）

検証バージョン: `@aws/agentcore` 最新版、`bedrock-agentcore@0.2.3`、Node.js 20 (Dockerfile) / v24 (ホスト)

### 必要な依存関係（Mastra 構成）

```sh
# ランタイム依存（dependencies）
npm install zod @mastra/core @ai-sdk/amazon-bedrock @aws-sdk/credential-providers bedrock-agentcore

# 開発依存（devDependencies）
npm install --save-dev typescript @types/node tsx
```

公式チュートリアルは `@strands-agents/sdk` と `@opentelemetry/auto-instrumentations-node` を入れるが、Mastra では不要。`package-lock.json` は `npm install` のたびに必ず更新すること（Dockerfile が `npm ci` を使うため lock とズレるとビルドエラー）。

### 最小限の agent.ts

```typescript
import { z } from "zod";
import { Agent } from "@mastra/core/agent";
import { createAmazonBedrock } from "@ai-sdk/amazon-bedrock";
import { fromNodeProviderChain } from "@aws-sdk/credential-providers";
import { BedrockAgentCoreApp } from "bedrock-agentcore/runtime";  // ← /runtime サブパス（npm TS版）

const bedrock = createAmazonBedrock({
  credentialProvider: fromNodeProviderChain()  // ← 明示必須（下記「クレデンシャル」参照）
});

const agent = new Agent({
  id: "assistant",
  name: "Assistant",
  instructions: "あなたは親切なアシスタントです。",
  model: bedrock("jp.anthropic.claude-sonnet-4-6"),
});

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema: z.object({ prompt: z.string() }),  // ← キーは prompt 固定
    process: async ({ prompt }) => {
      const result = await agent.generate(prompt);
      return result.text;  // ← 文字列で返す（オブジェクトは 500 を誘発）
    },
  },
});
app.run();
```

**注意**: Python SDK は `from bedrock_agentcore import BedrockAgentCoreApp`（`.runtime` サブモジュールはトレースが出なくなる）だが、TypeScript npm 版は `bedrock-agentcore/runtime` サブパスが正しい。言語で逆になる点に注意。

### 動作する Dockerfile（マルチステージ）

```dockerfile
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build          # = tsc → dist/agent.js を生成

FROM node:20-slim
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package*.json ./
ENV AWS_REGION=ap-northeast-1   # ← リージョンを焼き込む（下記参照）
RUN useradd -m bedrock_agentcore  # ← -u 1000 は付けない（下記参照）
USER bedrock_agentcore
EXPOSE 8080
CMD ["node", "dist/agent.js"]
```

### tsconfig.json（ESM 必須設定）

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "./dist",
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["*.ts"],
  "exclude": ["node_modules", "dist"]
}
```

`package.json` には `"type": "module"` が必要。

### ハマりポイント一覧

#### useradd -u 1000 でビルド失敗

公式ドキュメントの Dockerfile に `useradd -m -u 1000 bedrock_agentcore` とあるが、`node:20-slim` には UID 1000 の `node` ユーザーがすでに存在するため「UID 1000 is not unique」で `exit code 1`（= 「Container build failed」）。Python チュートリアルの Dockerfile をそのまま流用したドキュメント側のバグ。

**対処**: `-u 1000` を外す → `RUN useradd -m bedrock_agentcore`

#### agentcore dev は AWS_REGION を渡さない

`agentcore dev` はローカルの AWS クレデンシャルはコンテナに渡すが、`AWS_REGION` は渡さない（`~/.aws/config` もコンテナに入らない）。そのため `@ai-sdk/amazon-bedrock` がリージョン解決できずエラーになる：

```
AI_LoadSettingError: AWS region setting is missing.
```

**対処**: Dockerfile の実行ステージに `ENV AWS_REGION=<region>` を焼き込む（`agent.ts` の変更は不要。SDK が自動で拾う）。

#### @ai-sdk/amazon-bedrock のクレデンシャル問題

`@ai-sdk/amazon-bedrock` はデフォルトで環境変数（`AWS_ACCESS_KEY_ID` 等）からしかクレデンシャルを読まない。`agentcore dev` はクレデンシャルを `~/.aws` マウント＋`AWS_CONFIG_FILE` で渡すため、デフォルトのままだとローカル・本番の両方で `AWS credentials` 系エラーになる。

**対処**: `fromNodeProviderChain()` を `credentialProvider` に渡す。「環境変数 → 設定ファイル → SSO → コンテナロール」の順で解決し、ローカルでも本番でも動く。

```typescript
import { fromNodeProviderChain } from "@aws-sdk/credential-providers";
const bedrock = createAmazonBedrock({ credentialProvider: fromNodeProviderChain() });
```

#### モデル ID のプレフィックスと AWS_REGION は揃える

| モデル ID | Dockerfile の ENV AWS_REGION |
|-----------|------------------------------|
| `jp.anthropic.claude-sonnet-4-6` | `ap-northeast-1` |
| `us.anthropic.claude-sonnet-4-6` | `us-east-1` または `us-west-2` |

ズレると `ValidationException: inference profile not found` 系で落ちる。invoke ログで「最初数回 500、最後だけ成功」となっていたらたいていこれ。

#### bedrock-agentcore@0.2.3 のエラーが不透明な 500 になる

ハンドラやバリデーションでエラーが起きると、SDK 内蔵 `@fastify/sse` プラグインとの競合で `Attempted to send payload of invalid type 'object'` が発生し、UI には「Error: 500」としか出ない。

**対処**:
- `process` の戻り値は**文字列**にする（オブジェクトを返すとこのバグ経路を踏む）
- エラー診断は UI ではなくログを見る：`docker logs <devコンテナ名>`（ローカル）、`agentcore logs --runtime <名前> --since 30m`（デプロイ後）

#### リクエストキーは prompt 固定

`agentcore invoke "..."` も Inspector の Chat UI も `{"prompt": "..."}` でペイロードを送る。`requestSchema` を `message` 等にすると zod バリデーションが失敗し、上記の不透明な 500 になる。

#### agentcore.json に Python のプレースホルダが残る（Container では無視）

`agentcore add agent --build Container --language TypeScript` で生成しても、`agentcore.json` の `runtimes[0].entrypoint` は `"main.py"`、`runtimeVersion` は `"PYTHON_3_14"` のまま。**Container ビルドではこれらは無視される**（起動は Dockerfile の `CMD`、ランタイムはベースイメージで決まる）ため変更不要・変更しても影響なし。「`main.py` に直さなきゃ？」と焦る必要はない。

#### agentcore deploy のコンテナビルドは CodeBuild ARM64

本番ビルドは CodeBuild の ARM64 環境で走る。ローカルの `docker build` はあくまで事前確認用。`node:20-slim` はマルチアーキ対応なのでそのままで問題なし。アーキテクチャ固有のネイティブバイナリを含む場合は要注意。

### デバッグの基本動作（TypeScript Container）

| 症状 | 見るもの |
|------|---------|
| 「Container build failed」 | コードディレクトリで `docker build .` を直接実行 |
| 「Error: 500」（ローカル） | `docker logs <devコンテナ名>`（`"level":50` の行が真因） |
| 「Received error (500)」（デプロイ後） | `agentcore logs --runtime <名前> --since 30m` |
| TypeScript ビルドエラー | `npm run build`（= `tsc`）をローカルで実行 |

---

## 関連スキル

- `/kb-strands-agentcore` - Strands Agents フレームワーク（Agent作成、ツール定義、イベント処理）
- `/kb-agentcore-observability` - OpenTelemetry、ログ、メトリクス、トレース
- `/kb-agentcore-identity` - アウトバウンド認証（3LO/M2M/デコレータ分離/callback等）
- `/kb-amplify-cdk` - Amplify Gen2 + CDK（sandbox、本番デプロイ、Hotswap）
