# AWS関連

- AWSリージョンはバージニア北部（us-east-1）、オレゴン（us-west-2）、東京（ap-northeast-1）を使うことが多いです。
- ローカル環境での AWS 認証には SSO 認証を使用する。プロファイル一覧はプロジェクトスコープの設定を参照すること。
  - プロジェクトでどのアカウントを使うべきか不明な場合は、必ずみのるんに確認すること。
- Bedrock の Claude モデルは US クロスリージョン推論（`us.` プレフィックス）で最新の Sonnet を使う。モデルID は頻繁に更新されるため、使用時は https://platform.claude.com/docs/ja/build-with-claude/claude-on-amazon-bedrock を WebFetch で確認すること。

## プロジェクトスコープの個人設定（PC別にセットアップが必要）

以下は `/sync-claude-code-settings` の同期対象外のため、各PCで個別に設定する。

- `~/.claude/projects/<ホスト固有パス>/CLAUDE.md` / `memory/`

設定内容：① AWS SSO プロファイル一覧　② アカウントID・ドメイン等の詳細 → `memory/aws-accounts.md`　③ その他 PC・個人固有の情報

## AWS関連MCP・プラグイン構成

`agent-toolkit-for-aws`（公式）プラグイン導入済み。raw MCP は削除し、プラグインに統合済み（2026-06-21）：

| 種別 | 名称 | 用途 |
|------|------|------|
| Plugin MCP | `aws-mcp`（`mcp__aws-mcp__*`・aws-core） | `call_aws` で全 AWS API 直接呼び出し。`search_documentation`/`retrieve_skill`/`run_script` も |
| Plugin MCP | `awsknowledge`（`mcp__plugin_aws-agents_awsknowledge__*`・aws-agents） | AWS 公式 Knowledge MCP。`read_documentation`/`recommend` 等（認証不要） |
| Skills | `aws-core:*`（13個） | cdk / amplify / observability / iam / serverless 等の設計ガイド |
| Skills | `aws-agents:*`（7個） | agents-build / connect / debug / deploy / harden / optimize / get-started |

削除済み（プラグインでカバー）:
- `strands`（strands-agents-mcp-server）→ `aws-agents` plugin でカバー
- `bedrock-agentcore-mcp-server` → `aws-agents` plugin + `awsknowledge` でカバー

**判断ルール**：
- AWS API 呼び出し → `aws-mcp` の `call_aws`
- AWS ドキュメント検索 → `awsknowledge`（認証不要なので最優先）
- AgentCore 操作 → `aws-agents` plugin の skill / `awsknowledge` で対応
- 設計判断（CDK/Amplify/Observability 等） → 自動起動される `aws-core:*` / `aws-agents:*` skill

### aws-mcp が `✗ Failed to connect` のとき

`aws-mcp` は `uvx mcp-proxy-for-aws` で AWS リモート MCP に **SigV4 認証**接続する。`.mcp.json` に `--profile` 指定が無いため **`[default]` プロファイルの正常設定＋ SSO ログイン済み**が必須（または `AWS_PROFILE` を起動環境で固定）。`[default]` が壊れていると aws-mcp だけ接続失敗する（他の uvx 系 MCP は認証不要なので動く）。

修復：① `aws sts get-caller-identity --profile default` で確認 → ② `~/.aws/config` の `[default]` を正しい SSO 設定に直す（`sso_session`/`sso_account_id`/`sso_role_name`/`region`）→ ③ `aws sso login --profile default` → ④ Claude Code を `/exit` で完全再起動（MCP は起動時 1 回だけスポーン）。

## SSO・認証コマンドは Claude が自走する

`aws sso login` のようにブラウザ承認が必要な CLI は、Claude が Bash で自分で実行する（「ターミナルで実行してください」とユーザーに渡さない）。CLI がローカル Web サーバーを立ててブラウザを自動起動するので、ユーザーは承認ボタンを押すだけ。同様: `gcloud auth login` / `gh auth login` / `op signin`。

- これは**自分のアカウント認証**なので [`outbound-communication.md`](outbound-communication.md) の「他者の共有スペースへの発信」とは別物（事前確認不要）。

## AWS / Cloud Operations

- AWS CLI 実行前に必ず `aws sts get-caller-identity --profile <profile>` でセッション確認。失効していたら **Claude が `aws sso login --profile <profile>` を自走**。
- **CloudWatch Logs 調査**: `aws-mcp` の `call_aws` で Logs/Insights API を優先。クエリ文法や Alarm 設計は `aws-core:aws-observability` skill が自動起動。MCP が disconnected なら Bash の `aws logs` でよいが、**コマンドは必ず `aws` で始め、1 コマンド 1 呼び出し、先頭に `#` や `sleep` を付けない**。
