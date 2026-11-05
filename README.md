# みのるんのClaude Code設定

Claude Code の個人設定を、参考用に整理して公開しているリポジトリです。

このリポジトリの更新は終了しました。中身は最終版のまま残しています。

[Claude Codeライトユーザー目線で、万人受けする便利設定を紹介 - Qiita](https://qiita.com/minorun365/items/3711c0de2e2558adb7c8)

## 構成

```text
claude/                # Claude の設定フォルダ（本来は頭に "." が付く）
├── CLAUDE.md          # AGENTS.md の読み込みと、Claude Code 固有の補足
├── AGENTS.md          # Codex / Claude Code 共通の作業ガイド
├── settings.json      # 権限・フック・表示の設定
├── statusline.py      # ステータスライン
├── rules/             # 外部への発信と、チャットでの出力の形
├── hooks/             # 外部への書き込みの確認と、英語になった応答の差し戻し
├── agents/            # 調査を代行するカスタムエージェント
└── skills/            # 文章の書き方、コミット、ドキュメント同期のスキル
```

`settings.json` の権限は緩めにしてあります。そのまま使わず、自分の環境に合わせて絞ってください。

## 関連リポジトリ

用途ごとに分けたものは、次のリポジトリで公開しています。

- [claude-code-japanese-guard](https://github.com/minorun365/claude-code-japanese-guard)：英語になった応答を差し戻す hook
- [agent-builder-skills](https://github.com/minorun365/agent-builder-skills)：AI エージェントの Web アプリを作るためのスキル集
- [minorun-marp-skill](https://github.com/minorun365/minorun-marp-skill)：Marp でスライドを作るためのスキル

## ライセンス

[MIT](LICENSE)
