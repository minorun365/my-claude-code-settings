# みのるんのClaude Code設定

人気のコーディングAIエージェント、Claude Codeの個人設定ファイル集。
自分の設定を参考実装として公開しています。

[Claude Codeライトユーザー目線で、万人受けする便利設定を紹介 - Qiita](https://qiita.com/minorun365/items/3711c0de2e2558adb7c8)

## 構成

```text
claude/                # Claude設定フォルダ（本来は頭に"."が付く）
├── CLAUDE.md          # @AGENTS.md を読み込む最小エントリーポイント
├── AGENTS.md          # Codex / Claude Code共通の作業ガイド
├── settings.json      # 権限・フック・プラグイン・表示設定
├── statusline.py      # ステータスライン
├── rules/             # 外部発信、文章、ファイル操作、開発の罠などのルール
├── hooks/             # 外部発信コマンドを確認するフック
├── agents/            # カスタムエージェント
└── skills/            # カスタムスキルと技術ナレッジ
```

公開版は参考用に調整しています。アカウント名、端末固有パス、接続先、認証情報は含めていないので、必要な値は各自のローカル設定で指定してください。

## ライセンス

[MIT](LICENSE)
