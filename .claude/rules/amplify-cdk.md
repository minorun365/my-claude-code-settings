# Amplify Gen2 + CDK ナレッジ

Amplify Gen2とCDKの統合に関する学びを記録する。

## Amplify Gen2 基本構造

```
amplify/
├── auth/
│   └── resource.ts    # Cognito認証設定
├── agent/             # カスタムリソース（例：AgentCore）
│   └── resource.ts
└── backend.ts         # バックエンド統合
```

## カスタムCDKスタックの追加

```typescript
// amplify/backend.ts
import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';
import { createMyCustomResource } from './custom/resource';

const backend = defineBackend({ auth });

// カスタムスタックを作成
const customStack = backend.createStack('CustomStack');

// Amplifyの認証リソースを参照
const userPool = backend.auth.resources.userPool;
const userPoolClient = backend.auth.resources.userPoolClient;

// カスタムリソースを作成
const { endpoint } = createMyCustomResource({
  stack: customStack,
  userPool,
  userPoolClient,
});
```

## カスタム出力の追加

フロントエンドからカスタムリソースの情報にアクセスする方法：

```typescript
// amplify/backend.ts
backend.addOutput({
  custom: {
    myEndpointArn: endpoint.arn,
    environment: 'sandbox',
  },
});
```

```typescript
// フロントエンドでアクセス
import outputs from '../amplify_outputs.json';
const endpointArn = outputs.custom?.myEndpointArn;
```

## 環境分岐（sandbox vs 本番）

```typescript
// amplify/backend.ts
const branch = process.env.AWS_BRANCH;  // Amplify Consoleが設定
const isSandbox = !branch || branch === 'sandbox';
const nameSuffix = isSandbox ? 'dev' : branch;

// リソース名に環境サフィックスを付与
const runtimeName = `my_agent_${nameSuffix}`;  // my_agent_dev, my_agent_main
```

## sandbox環境

### 起動
```bash
npx ampx sandbox
```

### 特徴
- ファイル変更を検知して自動デプロイ（ホットリロード）
- `amplify_outputs.json` が自動生成される
- CloudFormationスタック名: `amplify-{appName}-{identifier}-sandbox-{hash}`

### Dockerビルド（AgentCore等）
- sandbox環境では `fromAsset()` でローカルビルド可能
- Mac ARM64でビルドできるなら `deploy-time-build` は不要

## 本番環境（Amplify Console）

### 制約
- Docker build 未サポート（2026/1時点）

### 回避策
1. GitHub ActionsでECRプッシュ → CDKでECR参照
2. sandboxと本番でビルド方法を分岐
3. Amplify ConsoleのDocker対応を待つ

## CDK Hotswap

- CDK v1.14.0〜 で Bedrock AgentCore Runtime に対応
- Amplify toolkit-lib の対応バージョンへの更新を待つ必要あり

## よくあるエラー

### amplify_outputs.json が見つからない
- sandbox が起動していない
- `npx ampx sandbox` を実行する

### カスタム出力が反映されない
- `backend.addOutput()` を追加後、sandbox再起動が必要
