# Amplify Gen2 and custom CDK basics

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
