# Frontend, storage, CloudFront, and Cognito

## 目次

- 開発時のトラブルシューティング
  - Tailwind: レスポンシブクラス変更がPC表示に反映されない
  - dotenv: .env.local が読み込まれない
- CloudFront + S3 OAC（匿名公開コンテンツ配信）
  - 概要
  - 実装例
  - backend.tsでの統合
  - AgentCore/Lambdaへの権限付与
  - defineStorage vs カスタムCDK
- Cognito検証ユーザーの自動作成（sandbox環境向け）
  - 概要
  - 課題
  - 解決策
  - 実装例
  - 環境変数（.env）
  - ポイント
  - 注意事項
  - 参考リンク
- Cognito User Migration Trigger（Lambda移行）
  - 概要
  - Amplify Gen2での実装
    - 1. Migration Lambda（defineFunction）
    - 2. auth/resource.ts にトリガー登録
    - 3. backend.ts でIAM権限 + AuthFlow設定
  - defineFunction で @aws-sdk/* を使う場合

## 開発時のトラブルシューティング

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

### dotenv: .env.local が読み込まれない

**症状**: `.env.local`に環境変数を設定したが、Node.js（Amplify CDK等）で読み込まれない

**原因**: `dotenv`パッケージはデフォルトで`.env`のみ読む。`.env.local`はVite/Next.jsの独自サポート

**解決策**: `.env.local` → `.env` にリネーム（Viteは`.env`も読むため互換性あり）

---

## CloudFront + S3 OAC（匿名公開コンテンツ配信）

### 概要

S3バケットを直接公開せず、CloudFront経由でのみアクセスを許可する構成。
`defineStorage`はCognito認証ユーザー向けなので、匿名公開にはカスタムCDKが必要。

### 実装例

```typescript
// amplify/storage/resource.ts
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { Construct } from 'constructs';

export class SharedContentConstruct extends Construct {
  public readonly bucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;

  constructor(scope: Construct, id: string) {
    super(scope, id);

    // S3バケット（パブリックアクセスブロック有効）
    // ⚠️ bucketName は指定しない → CFnが自動生成（グローバル一意性を保証、フォーク先でも衝突しない）
    this.bucket = new s3.Bucket(this, 'Bucket', {
      // bucketName を省略 → CDKベストプラクティス
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [{
        id: 'DeleteAfter7Days',
        expiration: cdk.Duration.days(7),  // 自動削除
      }],
    });

    // CloudFront（OAC経由でS3アクセス）
    this.distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(this.bucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
      },
    });
  }
}
```

### backend.tsでの統合

```typescript
// amplify/backend.ts
import { SharedContentConstruct } from './storage/resource';

const customStack = backend.createStack('SharedContentStack');
const sharedContent = new SharedContentConstruct(customStack, 'SharedContent');

// フロントエンドに出力
backend.addOutput({
  custom: {
    distributionDomain: sharedContent.distribution.distributionDomainName,
  },
});
```

### AgentCore/Lambdaへの権限付与

```typescript
runtime.addToRolePolicy(new iam.PolicyStatement({
  actions: ['s3:PutObject'],
  resources: [`${sharedContent.bucket.bucketArn}/*`],
}));

// 環境変数で渡す
environmentVariables: {
  SHARED_BUCKET: sharedContent.bucket.bucketName,
  CLOUDFRONT_DOMAIN: sharedContent.distribution.distributionDomainName,
}
```

### defineStorage vs カスタムCDK

| 観点 | defineStorage | カスタムCDK |
|------|---------------|------------|
| 認証ユーザー向け | ✅ 最適 | 可能 |
| 匿名公開 | ❌ 不向き | ✅ 最適 |
| CloudFront連携 | ❌ 非対応 | ✅ 柔軟 |
| Lifecycle Rule | 制限あり | ✅ 自由 |

---

## Cognito検証ユーザーの自動作成（sandbox環境向け）

### 概要

sandbox環境でログインテストを行うため、検証用ユーザーを自動作成したい場合の実装パターン。

### 課題

- `CfnUserPoolUser` だけでは **一時パスワード** しか設定できない
- 一時パスワードでログインすると `FORCE_CHANGE_PASSWORD` 状態になり、パスワード変更が必要
- 自動テストや開発時に面倒

### 解決策

`CfnUserPoolUser` + `AwsCustomResource`（adminSetUserPassword API）の組み合わせで **恒久パスワード** を設定する。

### 実装例

```typescript
// amplify/backend.ts
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as cr from 'aws-cdk-lib/custom-resources';

const isSandbox = !process.env.AWS_BRANCH;

if (isSandbox) {
  const testUserEmail = process.env.TEST_USER_EMAIL;
  const testUserPassword = process.env.TEST_USER_PASSWORD;

  if (testUserEmail && testUserPassword) {
    const userPool = backend.auth.resources.userPool;

    // ステップ1: ユーザー作成
    const testUser = new cognito.CfnUserPoolUser(stack, 'TestUser', {
      userPoolId: userPool.userPoolId,
      username: testUserEmail,
      userAttributes: [
        { name: 'email', value: testUserEmail },
        { name: 'email_verified', value: 'true' },  // メール確認済み
      ],
      messageAction: 'SUPPRESS',  // ウェルカムメールを抑制
    });

    // ステップ2: 恒久パスワード設定
    const setPassword = new cr.AwsCustomResource(stack, 'TestUserSetPassword', {
      onCreate: {
        service: 'CognitoIdentityServiceProvider',
        action: 'adminSetUserPassword',
        parameters: {
          UserPoolId: userPool.userPoolId,
          Username: testUserEmail,
          Password: testUserPassword,
          Permanent: true,  // 恒久パスワード（FORCE_CHANGE_PASSWORD回避）
        },
        physicalResourceId: cr.PhysicalResourceId.of(`TestUserPassword-${testUserEmail}`),
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: [userPool.userPoolArn],
      }),
    });

    // 依存関係: ユーザー作成後にパスワード設定
    setPassword.node.addDependency(testUser);
  }
}
```

### 環境変数（.env）

```bash
TEST_USER_EMAIL=test@example.com
TEST_USER_PASSWORD=TestPass123!
```

### ポイント

| 項目 | 説明 |
|------|------|
| `messageAction: 'SUPPRESS'` | ウェルカムメール送信を抑制 |
| `email_verified: 'true'` | メール確認済みとして登録 |
| `Permanent: true` | 恒久パスワード（初回変更不要） |
| `isSandbox` 判定 | 本番環境では作成しない |

### 注意事項

- 本番環境では `AWS_BRANCH` が設定されるため、この処理は実行されない
- スタック削除時にユーザーも自動削除される
- パスワードはCognito要件を満たす必要あり（8文字以上、大文字・小文字・数字・記号）

### 参考リンク

- [AdminSetUserPassword API](https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_AdminSetUserPassword.html)
- [CfnUserPoolUser CDK](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_cognito.CfnUserPoolUser.html)

---

## Cognito User Migration Trigger（Lambda移行）

### 概要

既存のCognitoユーザーを新しいUserPoolに透過的に移行する仕組み。ユーザーはいつも通りサインインするだけで自動移行される。

### Amplify Gen2での実装

#### 1. Migration Lambda（defineFunction）

```typescript
// amplify/auth/user-migration/resource.ts
import { defineFunction } from '@aws-amplify/backend';

export const userMigration = defineFunction({
  name: 'user-migration',
  entry: './handler.ts',
  environment: {
    OLD_USER_POOL_ID: process.env.OLD_USER_POOL_ID || '',
    OLD_USER_POOL_CLIENT_ID: process.env.OLD_USER_POOL_CLIENT_ID || '',
    OLD_ACCOUNT_ROLE_ARN: process.env.OLD_ACCOUNT_ROLE_ARN || '',
  },
  timeoutSeconds: 15,
});
```

#### 2. auth/resource.ts にトリガー登録

```typescript
import { defineAuth } from '@aws-amplify/backend';
import { userMigration } from './user-migration/resource';

export const auth = defineAuth({
  loginWith: { email: true },
  triggers: { userMigration },
});
```

#### 3. backend.ts でIAM権限 + AuthFlow設定

```typescript
// defineBackendにuserMigrationを登録
const backend = defineBackend({ auth, userMigration });

// Migration LambdaにSTS AssumeRole権限を付与
backend.userMigration.resources.lambda.addToRolePolicy(new iam.PolicyStatement({
  actions: ['sts:AssumeRole'],
  resources: [oldAccountRoleArn],
}));

// App ClientでUSER_PASSWORD_AUTHを有効化（移行期間中のみ）
const cfnClient = backend.auth.resources.userPoolClient.node
  .defaultChild as cognito.CfnUserPoolClient;
cfnClient.explicitAuthFlows = [
  'ALLOW_CUSTOM_AUTH',
  'ALLOW_USER_PASSWORD_AUTH',
  'ALLOW_USER_SRP_AUTH',
  'ALLOW_REFRESH_TOKEN_AUTH',
];
```

### defineFunction で @aws-sdk/* を使う場合

**Amplify Gen2の`defineFunction`はAWS SDKを自動でexternalにしない**。Lambda実行時にSDKは利用可能だが、ビルド時（esbuild）にモジュール解決できずエラーになる。

```bash
# 必要なSDKパッケージを明示的にインストール
npm install @aws-sdk/client-cognito-identity-provider @aws-sdk/client-sts
```
