# みのるんのClaude Code設定

Claude Code（Anthropic公式CLI）の個人設定ファイル集。

複数PCで共通利用する設定のみを管理します。機密情報を含まず、パブリック公開しても問題ない内容のみを扱います。

[Claude Codeライトユーザー目線で、万人受けする便利設定を紹介 - Qiita](https://qiita.com/minorun365/items/3711c0de2e2558adb7c8)


## 構成

```
.claude/
├── CLAUDE.md          # グローバル設定（基本方針、AWS設定など）
├── settings.json      # Claude Codeの設定
├── statusline.sh      # ステータスライン設定
├── agents/            # カスタムエージェント
├── rules/             # プロジェクト横断のナレッジベース
└── skills/            # カスタムスキル
```

## 使い方

`~/.claude/` に配置して使用。`/sync-settings` スキルで同期可能。
