---
name: kb-amplify-cdk
description: Amplify Gen2 + CDK のナレッジ。sandbox管理、本番デプロイ、Hotswap等
user-invocable: true
---

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

### Dockerビルド対応

デフォルトビルドイメージにはDockerが含まれていないが、**カスタムビルドイメージ**を設定することでDocker buildが可能。

```
public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0
```

### 設定手順

1. Amplify Console → 対象アプリ
2. **Hosting** → **Build settings** → **Build image settings** → **Edit**
3. **Build image** → **Custom Build Image** を選択
4. イメージ名を入力: `public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0`
5. **Save**

### カスタムビルドイメージの要件

- Linux（x86-64、glibc対応）
- cURL、Git、OpenSSH、Bash
- Node.js + NPM（推奨）

### 環境変数の設定

Amplify Console → **Environment variables** で設定:
- APIキー等の機密情報はここで設定
- CDKのビルド時に参照可能

## CDK Hotswap

- CDK v1.14.0〜 で Bedrock AgentCore Runtime に対応
- Amplify toolkit-lib の対応バージョンへの更新を待つ必要あり

### Amplify で AgentCore Hotswap を先行利用する方法（Workaround）

Amplify の公式アップデートを待たずに Hotswap を試す場合、`package.json` の `overrides` を使用：

```json
{
  "overrides": {
    "@aws-cdk/toolkit-lib": "1.14.0",
    "@smithy/core": "^3.21.0"
  }
}
```

| パッケージ | バージョン | 理由 |
|-----------|-----------|------|
| `@aws-cdk/toolkit-lib` | `1.14.0` | AgentCore Hotswap 対応版 |
| `@smithy/core` | `^3.21.0` | AWS SDK のリグレッションバグ対応 |

**注意事項**:
- 正攻法ではないので、お試し用途で使用
- Amplify の公式アップデートが来たら overrides を削除する
- 参考: [go-to-k/amplify-agentcore-cdk](https://github.com/go-to-k/amplify-agentcore-cdk)

## sandbox管理

### 正しい停止方法

sandboxを停止する際は `npx ampx sandbox delete` を使用する。

```bash
# 正しい方法
npx ampx sandbox delete --yes

# NG: pkillやkillでプロセスを強制終了すると状態が不整合になる
```

### 複数インスタンスの競合

**症状**:
```
[ERROR] [MultipleSandboxInstancesError] Multiple sandbox instances detected.
```

**原因**: 複数のsandboxプロセスが同時に動作している

**解決策**:
1. すべてのampxプロセスを確認
   ```bash
   ps aux | grep "ampx" | grep -v grep
   ```
2. `.amplify/artifacts/` をクリア
   ```bash
   rm -rf .amplify/artifacts/
   ```
3. `npx ampx sandbox delete --yes` で完全削除
4. 新しくsandboxを1つだけ起動

### ファイル変更が検知されない

**症状**: agent.pyなどを変更してもデプロイがトリガーされない

**原因**: sandboxが古い状態で動作している、または複数インスタンス競合

**解決策**:
1. sandbox deleteで完全削除
2. 新しくsandbox起動
3. ファイルをtouchしてトリガー
   ```bash
   touch amplify/agent/runtime/agent.py
   ```

### Docker未起動エラー

**症状**:
```
ERROR: Cannot connect to the Docker daemon at unix:///...
[ERROR] [UnknownFault] ToolkitError: Failed to build asset
```

**原因**: Docker Desktopが起動していない

**解決策**:
1. Docker Desktopを起動
2. ファイルをtouchしてデプロイ再トリガー

## deploy-time-build（本番環境ビルド）

### 概要

sandbox環境ではローカルでDockerビルドできるが、本番環境（Amplify Console）ではCodeBuildでビルドする必要がある。`deploy-time-build` パッケージを使用してビルドをCDK deploy時に実行する。

### 環境分岐の実装

```typescript
// amplify/agent/resource.ts
import * as ecr_assets from 'aws-cdk-lib/aws-ecr-assets';

const isSandbox = !branch || branch === 'sandbox';

const artifact = isSandbox
  ? agentcore.AgentRuntimeArtifact.fromAsset(runtimePath)  // ローカルビルド
  : agentcore.AgentRuntimeArtifact.fromAsset(runtimePath, {
      platform: ecr_assets.Platform.LINUX_ARM64,
      bundling: {
        // deploy-time-build でCodeBuildビルド
      },
    });
```

### ⚠️ コンテナイメージのタグ指定に関する重要な注意

**`tag: 'latest'` を指定すると、コード変更時にAgentCoreランタイムが更新されない問題が発生する。**

#### 問題の仕組み

1. コードをプッシュ → ECRに新イメージがプッシュ（タグ: `latest`）
2. CDKがCloudFormationテンプレートを生成
3. CloudFormation: 「タグは同じ `latest` だから変更なし」と判断
4. **ターゲットリソース（AgentCore Runtime等）が更新されない**

#### NG: 固定タグを使用

```typescript
containerImageBuild = new ContainerImageBuild(stack, 'ImageBuild', {
  directory: path.join(__dirname, 'runtime'),
  platform: Platform.LINUX_ARM64,
  tag: 'latest',  // ❌ CloudFormationが変更を検知できない
});
```

#### OK: タグを省略してassetHashを使用

```typescript
containerImageBuild = new ContainerImageBuild(stack, 'ImageBuild', {
  directory: path.join(__dirname, 'runtime'),
  platform: Platform.LINUX_ARM64,
  // tag を省略 → assetHashベースのタグが自動生成される
});

// 古いイメージを自動削除（直近N件を保持）
// ⚠️ repository は IRepository 型のため、型アサーションが必要
import * as ecr from 'aws-cdk-lib/aws-ecr';

(containerImageBuild.repository as ecr.Repository).addLifecycleRule({
  description: 'Keep last 5 images',
  maxImageCount: 5,
  rulePriority: 1,
});
```

#### ⚠️ `addLifecycleRule` の型エラーについて

`containerImageBuild.repository` は `IRepository` インターフェース型で返される。`addLifecycleRule()` メソッドは `Repository` クラス固有のため、直接呼び出すとTypeScriptエラーになる。

```typescript
// ❌ TypeScriptエラー: Property 'addLifecycleRule' does not exist on type 'IRepository'
containerImageBuild.repository.addLifecycleRule({...});

// ✅ 型アサーションで解決
(containerImageBuild.repository as ecr.Repository).addLifecycleRule({...});
```

**なぜこうなるか**: deploy-time-buildは外部から既存リポジトリを渡せるよう `IRepository` 型で公開している。実際には内部で `new Repository()` を生成しているため、型アサーションで動作する。

**注意**: 型アサーションは型安全性を失う。将来ライブラリが変更されると壊れる可能性あり。

**OSS改善提案**: [Issue #76](https://github.com/tmokmss/deploy-time-build/issues/76) で `lifecycleRules` オプション追加を提案済み。

#### 比較表

| 項目 | `tag: 'latest'` | タグ省略（推奨） |
|------|-----------------|-----------------|
| デプロイ時の更新 | ❌ 反映されないことがある | ✅ 常に反映される |
| ECRイメージ数 | 1つのみ | 蓄積（要Lifecycle Policy） |
| ロールバック | ❌ 不可 | ✅ 可能 |

### 参考

- [deploy-time-build](https://github.com/tmokmss/deploy-time-build)

---

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

## よくあるエラー

### amplify_outputs.json が見つからない
- sandbox が起動していない
- `npx ampx sandbox` を実行する

### カスタム出力が反映されない
- `backend.addOutput()` を追加後、sandbox再起動が必要
