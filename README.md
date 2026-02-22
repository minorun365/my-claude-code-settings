# みのるんのClaude Code設定

人気のコーディングAIエージェント、Claude Codeの個人設定ファイル集。
自分の設定を参考実装として公開しています。

[Claude Codeライトユーザー目線で、万人受けする便利設定を紹介 - Qiita](https://qiita.com/minorun365/items/3711c0de2e2558adb7c8)

## 構成

```
.claude.json           # MCPサーバーの設定（機密情報はマスク済み）
claude/                # Claude設定フォルダ（本来は頭に"."が付く）
├── CLAUDE.md          # ユーザーメモリー（グローバル指示）
├── settings.json      # Claude Codeの設定
├── statusline.sh      # ステータスライン設定
├── agents/            # カスタムエージェント
└── skills/            # カスタムスキル・ナレッジベース
    ├── kb-*/          # 技術ナレッジ（AWS, React, LINE Bot等）
    └── sync-*/        # 同期系ユーティリティ
```

## 参考にする場合

このリポジトリの設定ファイルを自分の環境に取り込むには、必要な部分を `~/.claude/` 配下にコピーしてください。

```bash
# 例：スキルをコピー
cp -r claude/skills/kb-strands-agentcore/ ~/.claude/skills/

# 例：エージェント定義をコピー
cp claude/agents/*.md ~/.claude/agents/
```

- `claude/CLAUDE.md` はみのるん個人向けの設定例です。自分の環境に合わせてカスタマイズしてください。
- `.claude.json` のMCPサーバー設定は `<MASKED>` 部分を自分の認証情報に置き換えてください。
