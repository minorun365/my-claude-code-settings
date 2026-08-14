# Sandbox and production operations

## 目次

- sandbox環境
  - 起動
  - 特徴
  - 環境変数の注意点
  - デプロイ完了の確認
  - Dockerビルド（AgentCore等）
- 本番環境（Amplify Console）
  - Dockerビルド対応
  - 設定手順
  - カスタムビルドイメージの要件
  - 環境変数の設定
  - amplify.yml カスタマイズ時の注意
  - デプロイ失敗時のデバッグ
  - Dockerfile ベースイメージ: ECR Public を使う
- CDK Hotswap
  - Amplify で AgentCore Hotswap を先行利用する方法（Workaround）
- sandbox管理
  - 正しい停止方法
  - 複数インスタンスの競合
  - ファイル変更が検知されない
  - Docker未起動エラー
- deploy-time-build（本番環境ビルド）
  - 概要
  - 環境分岐の実装
  - ⚠️ コンテナイメージのタグ指定に関する重要な注意
    - 問題の仕組み
    - NG: 固定タグを使用
    - OK: タグを省略してassetHashを使用
    - ⚠️ `addLifecycleRule` の型エラーについて
    - 比較表
  - 参考

## sandbox環境

### 起動
```bash
npx ampx sandbox
```

### 特徴
- ファイル変更を検知して自動デプロイ（ホットリロード）
- `amplify_outputs.json` が自動生成される
- CloudFormationスタック名: `amplify-{appName}-{identifier}-sandbox-{hash}`

### 環境変数の注意点

`npx ampx sandbox` は `.env` ファイルを自動読み込みしない。CDKコード内で `process.env.XXX` を参照する環境変数は、sandbox起動前にシェルへ読み込む必要がある。

```bash
# NG: .envの値が渡らず空文字になる
npx ampx sandbox

# OK: .envを読み込んでから起動
export $(grep -v '^#' .env | grep -v '^$' | xargs) && npx ampx sandbox
```

**典型的な症状**: APIキー等を `process.env` 経由でランタイム環境変数に渡している場合、sandboxでは空文字がセットされ、実行時にAPIエラーになる。

### デプロイ完了の確認

sandbox起動後はバックグラウンド実行してログをこまめにポーリングし、以下のメッセージが出るまで待つ：

```
✔ Deployment completed in XXX seconds
[Sandbox] Watching for file changes...
File written: amplify_outputs.json
```

ファイル変更によるHotswapデプロイ時も同様に完了を確認すること。

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

### amplify.yml カスタマイズ時の注意

`amplify.yml` をカスタマイズすると、デフォルトの `npm install` が自動実行されなくなる。`preBuild` で `npm ci` を明示的に実行する必要がある。

```yaml
version: 1
backend:
  phases:
    preBuild:
      commands:
        - npm ci  # カスタムamplify.ymlでは自動実行されないため明示必須
    build:
      commands:
        - npx ampx pipeline-deploy --branch $AWS_BRANCH --app-id $AWS_APP_ID
frontend:
  phases:
    build:
      commands:
        - npm ci
        - npm run build
  artifacts:
    baseDirectory: dist
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
```

### デプロイ失敗時のデバッグ

`ampx pipeline-deploy` に `--debug` を付けると詳細なエラーログが出力される。特に `CDKAssetPublishError` のような抽象的なエラーの真の原因を特定するのに有効。

```yaml
# デバッグ時のみ使用
- npx ampx pipeline-deploy --branch $AWS_BRANCH --app-id $AWS_APP_ID --debug
```

### Dockerfile ベースイメージ: ECR Public を使う

`deploy-time-build` の CodeBuild から Docker Hub にイメージを pull すると、未認証扱いになりレートリミット（100 pulls/6h）に引っかかる。**ECR Public Gallery を使えばレートリミットなし。**

```dockerfile
# NG: Docker Hub → レートリミットで 429 Too Many Requests
FROM python:3.13-slim

# OK: ECR Public → レートリミットなし
FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm
```

Docker Hub の公式イメージはほぼすべて `public.ecr.aws/docker/library/` にミラーされている。

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
