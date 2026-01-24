# my-claude-code-settings

Claude Code（Anthropic公式CLI）の個人設定ファイル集。

## 構成

```
.claude/
├── CLAUDE.md      # グローバル設定（基本方針、AWS設定など）
├── settings.json  # Claude Codeの設定
├── skills/        # カスタムスキル
└── ...

rules/             # プロジェクト横断のナレッジベース
├── aws-learnings.md       # AWS関連の学び
├── llm-app-patterns.md    # LLMアプリ開発パターン
└── troubleshooting.md     # トラブルシューティング集
```

## 使い方

`~/.claude/` に配置して使用。このリポジトリは公開用テンプレートのため、実際の運用ファイルとは別管理。

## 参考

- [Claude Code公式ドキュメント](https://docs.anthropic.com/en/docs/claude-code)
