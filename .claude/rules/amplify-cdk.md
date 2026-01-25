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

### 参考

- [deploy-time-build](https://github.com/tmokmss/deploy-time-build)

---

## よくあるエラー

### amplify_outputs.json が見つからない
- sandbox が起動していない
- `npx ampx sandbox` を実行する

### カスタム出力が反映されない
- `backend.addOutput()` を追加後、sandbox再起動が必要
