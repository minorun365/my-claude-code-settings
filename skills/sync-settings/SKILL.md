---
name: sync-settings
description: Claude Codeの設定（rules、skills、CLAUDE.md）をGitHubのSettingsリポジトリに同期・プッシュする
user-invocable: true
---

# GitHub設定同期

`~/.claude/` 配下の設定をGitHubのSettingsリポジトリに同期してプッシュします。

## 同期対象

| ソース | 同期先 |
|--------|--------|
| `~/.claude/rules/` | `~/git/minorun365/my-claude-code-settings/rules/` |
| `~/.claude/skills/` | `~/git/minorun365/my-claude-code-settings/skills/` |
| `~/.claude/CLAUDE.md` | `~/git/minorun365/my-claude-code-settings/.claude/CLAUDE.md` |

## 実行手順

1. **現在の設定を確認**
   ```bash
   ls -la ~/.claude/rules/
   ls -la ~/.claude/skills/
   ```

2. **Settingsリポジトリにコピー**
   ```bash
   cp -r ~/.claude/rules/* ~/git/minorun365/my-claude-code-settings/rules/
   cp -r ~/.claude/skills/* ~/git/minorun365/my-claude-code-settings/skills/
   cp ~/.claude/CLAUDE.md ~/git/minorun365/my-claude-code-settings/.claude/
   ```

3. **差分を確認**
   ```bash
   cd ~/git/minorun365/my-claude-code-settings
   git status
   git diff
   ```

4. **コミットとプッシュ**
   - 変更内容を確認してユーザーに報告
   - ユーザーの承認を得てからコミット・プッシュ
   ```bash
   git add .
   git commit -m "設定同期"
   git push
   ```

## 注意事項

- 機密情報（APIキー等）が含まれていないか確認
- `.gitignore` で除外すべきファイルがないか確認
- プッシュ前に必ずユーザーに確認を取る
