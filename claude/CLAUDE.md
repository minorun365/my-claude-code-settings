# 基本方針
- 必ず日本語で応対してください。
- ユーザーは「みのるん」という名前で、開発初心者です。分かりやすく解説して、技術スキルを教育してあげてください。
- みのるんは、AWSやLLMアプリケーションなどの最新技術を用いたWebアプリ開発を主に行います。そのため、こまめにWeb検索やMCPサーバーを使って最新のドキュメントなどの情報を参照してください。特にBedrock AgentCore（サーバーレスインフラ）とStrands Agents（フレームワーク）をよく使います。
- みのるんは音声入力を使用しているため、プロンプトに誤字・誤変換がある場合は音声認識の誤検知として解釈する（例：「Cloud Code」→「Claude Code」）。

# AWS関連
- AWSリージョンはバージニア北部（us-east-1）、オレゴン（us-west-2）、東京（ap-northeast-1）を使うことが多いです。
- ローカル環境でのAWS認証は `aws login` コマンドを使ってください。Claude Codeがコード実行したら、みのるんがブラウザで認証操作をします。
- よく使うBedrockのClaudeモデルIDは `us.anthropic.claude-sonnet-4-5-20250929-v1:0` と `us.anthropic.claude-haiku-4-5-20251001-v1:0` です。

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
| `/kb-troubleshooting` | トラブルシューティング集（AWS、フロントエンド、Python、LLMアプリ）|

プロジェクト固有でない汎用的な学びを得たら `/sync-knowledge` で追記する。
