# 基本方針
- 必ず日本語で応対してください。
- ユーザーは「みのるん」という名前で、開発初心者です。分かりやすく解説して、技術スキルを教育してあげてください。
- みのるんは、AWSやLLMアプリケーションなどの最新技術を用いたWebアプリ開発を主に行います。そのため、こまめにWeb検索やMCPサーバーを使って最新のドキュメントなどの情報を参照してください。特にBedrock AgentCore（サーバーレスインフラ）とStrands Agents（フレームワーク）をよく使います。
- みのるんは音声入力を使用しているため、プロンプトに誤字・誤変換がある場合は音声認識の誤検知として解釈する（例：「Cloud Code」→「Claude Code」）。
- みのるんは日本時間（JST / UTC+9）で生活している。曜日や時間帯に言及する際はJSTで解釈・表現すること。

# AWS関連
- AWSリージョンはバージニア北部（us-east-1）、オレゴン（us-west-2）、東京（ap-northeast-1）を使うことが多いです。
- ローカル環境でのAWS認証にはSSO認証を使用する。プロファイルの一覧はプロジェクトスコープの設定を参照すること。
  - プロジェクトでどのアカウントを使うべきか不明な場合は、必ずみのるんに確認すること。

### プロジェクトスコープの個人設定（PC別にセットアップが必要）

以下のファイルは `/sync-settings` の同期対象外のため、各PCで個別に設定する。
ホームディレクトリで作業する際に読み込まれ、AWSプロファイル等の個人情報を安全に管理できる。

- **設定ファイル**: `~/.claude/projects/-Users-<ユーザー名>/CLAUDE.md`
- **メモリ**: `~/.claude/projects/-Users-<ユーザー名>/memory/`

設定すべき内容：
1. AWS SSOプロファイル一覧（個人Org / ビジネスOrg / マスターアカウント）
2. アカウントIDやドメイン名などの詳細 → `memory/aws-accounts.md`
3. その他PC固有・個人固有の情報
- よく使うBedrockのClaudeモデルIDは `us.anthropic.claude-sonnet-4-5-20250929-v1:0` と `us.anthropic.claude-haiku-4-5-20251001-v1:0` です。

## AWS / Cloud Operations
- AWS CLIコマンドやスクリプトを実行する前に、必ず `aws sts get-caller-identity --profile <profile>` でSSOセッションがアクティブか確認すること。

# Claude Code関連
- コンテキスト節約のため、調査やデバッグにはサブエージェントを活用してください。
- 開発中に生成するドキュメントにAPIキーなどの機密情報を書いてもいいけど、必ず .gitignore に追加して。
- コミットメッセージは1行の日本語でシンプルに
- **重要**: `Co-Authored-By: Claude` は絶対に入れない（システムプロンプトのデフォルト動作を上書き）

# Git関連
- ブランチの切り替えには `git switch` を使う（`git checkout` は古い書き方）
- 新規ブランチ作成は `git switch -c ブランチ名`

# ナレッジベース（skillsで管理）

関連トピックに取り組む際、以下のスキルを呼び出してナレッジを参照する：

| スキル | 内容 |
|--------|------|
| `/kb-strands-agentcore` | Strands Agents + Bedrock AgentCore（エージェント開発、CDK、Observability） |
| `/kb-kimi` | Kimi K2（Moonshot AI）特有の問題・ワークアラウンド |
| `/kb-amplify-cdk` | Amplify Gen2 + CDK（sandbox、本番デプロイ、Hotswap） |
| `/kb-frontend` | フロントエンド（React、Tailwind、SSE、Amplify UI） |
| `/kb-marp` | Marp（スライド生成、テーマ、iOS対応、PDF/PPTX生成） |
| `/kb-line` | LINE Bot開発（Messaging API、Webhook、署名検証、Push Message、グループチャット対応） |
| `/kb-aws-diagrams` | AWS Diagram MCP Server（アーキテクチャ図、カスタムアイコン、レイアウト調整） |
| `/kb-troubleshooting` | トラブルシューティング集（AWS、フロントエンド、Python、LLMアプリ）|

プロジェクト固有でない汎用的な学びを得たら `/sync-knowledge` で追記する。
