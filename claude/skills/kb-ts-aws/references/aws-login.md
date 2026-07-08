# aws login コマンド（v2.32.0〜）

## aws login コマンド（v2.32.0〜）

### 概要

AWS CLI v2.32.0（2025年11月）で追加された新しい認証方式。コンソール認証情報（ルートユーザー・IAMユーザー・フェデレーションID）を使い、ブラウザ経由でCLIにログインする。長期アクセスキーの作成・管理が不要になる。

### `aws login` vs `aws sso login` の使い分け

| 観点 | `aws login` | `aws sso login` |
|------|-------------|-----------------|
| 対象 | コンソール認証情報（root / IAMユーザー / フェデレーション） | IAM Identity Center（旧AWS SSO） |
| 向いているケース | 個人アカウント、素早いプロトタイピング | 企業・組織で複数アカウントを管理 |
| 事前設定 | ほぼ不要（ブラウザで完結） | `aws configure sso` で設定が必要 |
| 設定キー | `login_session = arn:aws:iam::...` | `sso_start_url`, `sso_account_id` 等 |
| キャッシュ | `~/.aws/login/cache` | `~/.aws/sso/cache` |
| 一時認証情報 | 15分ごとに自動リフレッシュ、最大12時間 | セッション有効期間内 |

**判断基準**: IAM Identity Centerで複数アカウントを管理しているなら `aws sso login` を継続。個人アカウントで手軽に始めたいなら `aws login` が便利。

### 基本操作

```bash
aws login                          # デフォルトプロファイルでログイン
aws login --profile personal       # 名前付きプロファイルでログイン
aws login --remote                 # ブラウザなし環境（コードを手動入力）
aws logout                         # ログアウト
aws logout --all                   # すべてのプロファイルからログアウト
```

### 設定例（`~/.aws/config`）

```ini
# aws login 用（個人アカウント）
[profile personal]
login_session = arn:aws:iam::111111111111:user/myuser
region = us-east-1

# aws sso login 用（組織アカウント）は従来通り
[profile work]
sso_start_url = https://myorg.awsapps.com/start
sso_account_id = 222222222222
sso_role_name = DeveloperAccess
region = ap-northeast-1
```

### IAM権限の前提条件

- **ルートユーザー**: 追加権限不要
- **IAMユーザー**: `SignInLocalDevelopmentAccess` マネージドポリシーのアタッチが必要

### はまりどころ

#### 1. AWS CRT ライブラリが必須（Python SDK）

Boto3/botocore で `aws login` の認証情報を使うには **AWS CRT（Common Runtime）が必須**。デフォルトでは含まれていない。

```bash
# pip の場合
pip install "botocore[crt]"

# uv の場合
uv add 'botocore[crt]'
```

Strands Agents SDK も Boto3 に依存しているため、CRT未インストールだと `aws login` 認証情報が使えない。

#### 2. 古いアクセスキーが優先される（重大）

`~/.aws/credentials` に長期アクセスキーが残っていると、`aws login` でログインしていてもアクセスキーが優先される。意図しないアカウントが操作されるリスクがあるため、移行時は古いキーを削除する。

#### 2.1 認証成功後に「Authentication failed（無効なリクエスト）」→ 実は signin 権限不足

**症状**: パスワード+MFA（パスキー）認証は成功するのに、直後のOAuth承認段階でブラウザに「Authentication failed / 無効なリクエスト」。通常方式・`--remote` 方式とも同じエラー。エラー文言からは有効期限切れやURL破損に見えるが別物。

**原因**: `signin:AuthorizeOAuth2Access` の権限不足。認可API呼び出しのIAMエラーが「無効なリクエスト」という一見無関係なエラーに化ける。次の2パターンがある：

1. `SignInLocalDevelopmentAccess` マネージドポリシー未付与（implicit deny）
2. **`NotAction` + explicit deny 型のMFA強制ポリシーに巻き込まれる**。`signin:AuthorizeOAuth2Access` / `signin:CreateOAuth2Token` は2025年11月新設のアクションのため、それ以前に設計された「NotActionリスト以外は全deny」型ポリシーが自動的にブロックする

**対処**: 管理者に ① `SignInLocalDevelopmentAccess` のアタッチ ② MFA強制ポリシーの `NotAction` へ signin 2アクション追加、を依頼する。

#### 2.2 マルチセッションブラウザで別アカウントに誤ログイン

**症状**: ブラウザに複数のAWSセッションがある状態で `aws login` すると、「アクティブセッションで続行」で**意図しない別アカウントの一時クレデンシャルが発行**され、`~/.aws/config` の該当プロファイルに `login_session` として上書きされる。

**対処**（Claude Code から支援する場合の定石）:

```bash
# ブラウザ自動起動を抑止して認証URLだけ取得（localhostコールバック方式）
BROWSER=/usr/bin/false aws login --profile <p> > login.log 2>&1 &
# → URLをユーザーに渡し、シークレットウィンドウで開いてもらう
#   （既存セッションが一切効かないので誤アカウント防止。コールバックは 127.0.0.1 なので自動完結）
```

- `--remote` 方式（認証コード手動貼り付け）でも回避できるが、localhostコールバック方式の方がユーザーの手数が少ない
- `--remote` で認証コードを後から注入したい場合は FIFO を使う: `mkfifo p; sleep 1800 > p & aws login --remote < p > log 2>&1 &` → 後で `echo <code> > p`
- OAuth `state` の有効期限は短い。URL発行〜認証完了はユーザーがブラウザ前にいるタイミングで一気にやる
- 誤ログイン後の掃除は config の該当プロファイルから `login_session` 行を削除

#### 3. Amplify Gen2 (`ampx`) の互換性

- リリース当初は `npx ampx sandbox` が `aws login` 認証情報を認識できず `Failed to load default AWS credentials` エラー
- **`@aws-amplify/backend-cli` v1.8.1 以降で修正済み** → `npm update @aws-amplify/backend-cli`

#### 3.1 Amplify Gen2 を CLI (`aws amplify create-app`) で作成するとサービスロール未設定

**症状**: `aws amplify create-app` で作ったアプリをビルドすると、backend フェーズの `npx ampx pipeline-deploy` が次のエラー：

```
BootstrapDetectionError: Unable to detect CDK bootstrap stack due to permission issues.
AccessDeniedException: User: ...AemiliaControlPlaneLambda-CodeBuildRole... is not authorized to
perform: ssm:GetParameter on resource: arn:aws:ssm:us-east-1:<account>:parameter/cdk-bootstrap/hnb659fds/version
```

**原因**: ブラウザUI経由で作成した場合は Amplify がサービスロール（`AmplifyBackendDeployFullAccess` 付き）を自動で用意するが、`aws amplify create-app` CLI は `iamServiceRoleArn` を指定しない限り未設定のまま。`pipeline-deploy` が CDK bootstrap の SSM パラメータを読めずに失敗する。

**対処**:
```bash
# サービスロール作成
aws iam create-role --role-name <app>-amplify-service-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"amplify.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name <app>-amplify-service-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmplifyBackendDeployFullAccess

# アプリに紐付け
aws amplify update-app --app-id <APP_ID> \
  --iam-service-role-arn arn:aws:iam::<ACCOUNT>:role/<app>-amplify-service-role

# 再ビルド
aws amplify start-job --app-id <APP_ID> --branch-name main --job-type RELEASE
```

**補足**: SSR のコンピュートロール（`compute-role-arn`）とは別物。SSR コンピュートロールは Lambda@Edge 的な SSR 実行用、サービスロールは Amplify build 時の AWS API 操作用。

#### 3.2 Amplify Gen2 `npm ci` と package-lock.json 不整合

**症状**: Amplify build の backend フェーズで次のエラー：

```
npm error `npm ci` can only install packages when your package.json and
package-lock.json or npm-shrinkwrap.json are in sync.
Missing: fast-xml-parser@X.X.X from lock file
Missing: @aws-sdk/eventstream-handler-node@X.X.X from lock file
```

**原因**: Amplify Gen2 backend の `npx ampx pipeline-deploy` が内部で追加パッケージを解決する挙動により、lock file と node_modules の整合が崩れる。特に `@smithy/eventstream-codec` / `fast-xml-parser` 等の transitive dep で発生しやすい。ローカルで `npm install` → push しても、`npm ci --dry-run` でさえ同じエラーが出るため、単純な lock 再生成では解決しない。

**対処**: `amplify.yml` の `npm ci` を `npm install` に置き換える：

```yaml
backend:
  phases:
    build:
      commands:
        # ❌ npm ci --cache .npm --prefer-offline
        - npm install --no-audit --no-fund
        - npx ampx pipeline-deploy --branch $AWS_BRANCH --app-id $AWS_APP_ID
```

CI キャッシュ効率は落ちるが確実性優先。読者向けテンプレートに `npm ci` を書く場合は、この罠を注記しておくと親切。

#### 4. Terraform の互換性（Go SDK）

Terraform の Go SDK は `login_session` を未サポート（2026年1月時点でオープンIssueあり）。回避策として `credential_process` を使用：

```ini
[profile dev]
role_arn = arn:aws:iam::123456789012:role/MyRole
credential_process = aws configure export-credentials --profile default --format process
```

### トラブルシューティング

| エラー / 症状 | 原因 | 解決策 |
|-------------|------|--------|
| Boto3 で認証情報を読み込めない | CRT 未インストール | `pip install "botocore[crt]"` |
| `ExpiredToken` / 意図しないアカウント | 古いアクセスキーが優先 | `~/.aws/credentials` の古いキーを削除 |
| `Failed to load default AWS credentials` (ampx) | Amplify CLI が古い | `npm update @aws-amplify/backend-cli`（v1.8.1+） |
| Terraform で `only one credential type` | Go SDK 未対応 | `credential_process` で回避 |
| ブラウザが開かない | SSH 接続先等 | `aws login --remote` を使用 |

