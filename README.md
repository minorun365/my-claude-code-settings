# みのるんのClaude Code設定

人気のコーディングAIエージェント、Claude Codeの個人設定ファイル集。
自分の設定を参考実装として公開しています。

[Claude Codeライトユーザー目線で、万人受けする便利設定を紹介 - Qiita](https://qiita.com/minorun365/items/3711c0de2e2558adb7c8)

## 構成

```
.claude.json           # MCPサーバーの設定（機密情報はマスク済み）
claude/                # Claude設定フォルダ（本来は頭に"."が付く）
├── CLAUDE.md          # ユーザーメモリー（Claude Code固有の差分）
├── AGENTS.md          # Codex / Claude Code 共通ルールの正本
├── settings.json      # Claude Codeの設定（permissions / hooks / plugins等）
├── statusline.sh      # ステータスライン設定
├── rules/             # 詳細ルール集（Git運用・外部発信・開発ルール等）
├── hooks/             # フック（外部発信コマンドのブロック等）
├── agents/            # カスタムエージェント
└── skills/            # カスタムスキル・ナレッジベース
    ├── kb-*/          # 技術ナレッジ（AWS, AgentCore, フロントエンド等）
    ├── sync-*/        # 同期系ユーティリティ
    └── その他        # commit-push, writing-guide 等のワークフロー
```
