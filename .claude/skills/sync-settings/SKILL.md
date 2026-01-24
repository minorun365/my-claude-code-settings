---
name: sync-settings
description: Claude Codeの共通設定（rules、skills、CLAUDE.md）をGitHubリポジトリと双方向同期する
user-invocable: true
---

# GitHub設定同期

Claude Codeの**共通設定のみ**をGitHubリポジトリと双方向同期します。

## 同期対象（共通設定）

| ローカル | リポジトリ |
|----------|------------|
| `~/.claude/rules/` | `.claude/rules/` |
| `~/.claude/skills/` | `.claude/skills/` |
| `~/.claude/CLAUDE.md` | `.claude/CLAUDE.md` |

## 同期対象外（PC固有設定）

以下はPC固有のため**同期しない**：

- `~/.claude/settings.json` - 権限、hooks、statusLine等（PC固有パスやOS依存）
- `~/.claude/hooks/` - フックスクリプト
- `~/.claude/projects/` - プロジェクト固有設定
- `~/.claude/plugins/` - プラグイン設定
- その他キャッシュ、履歴、デバッグログ等

## リポジトリパス

```
~/git/minorun365/my-claude-code-settings/
```

## 実行手順

### Push（ローカル → リポジトリ）

1. **差分確認**
   ```bash
   diff -rq ~/.claude/rules/ ~/git/minorun365/my-claude-code-settings/.claude/rules/
   diff -rq ~/.claude/skills/ ~/git/minorun365/my-claude-code-settings/.claude/skills/
   diff ~/.claude/CLAUDE.md ~/git/minorun365/my-claude-code-settings/.claude/CLAUDE.md
   ```

2. **同期実行**
   ```bash
   rsync -av --delete ~/.claude/rules/ ~/git/minorun365/my-claude-code-settings/.claude/rules/
   rsync -av --delete ~/.claude/skills/ ~/git/minorun365/my-claude-code-settings/.claude/skills/
   cp ~/.claude/CLAUDE.md ~/git/minorun365/my-claude-code-settings/.claude/
   ```

3. **コミット・プッシュ**（ユーザー確認後）
   ```bash
   cd ~/git/minorun365/my-claude-code-settings
   git add -A
   git status
   git commit -m "設定同期"
   git push
   ```

### Pull（リポジトリ → ローカル）

1. **リポジトリを最新化**
   ```bash
   cd ~/git/minorun365/my-claude-code-settings
   git pull
   ```

2. **差分確認**
   ```bash
   diff -rq ~/git/minorun365/my-claude-code-settings/.claude/rules/ ~/.claude/rules/
   diff -rq ~/git/minorun365/my-claude-code-settings/.claude/skills/ ~/.claude/skills/
   diff ~/git/minorun365/my-claude-code-settings/.claude/CLAUDE.md ~/.claude/CLAUDE.md
   ```

3. **同期実行**（ユーザー確認後）
   ```bash
   rsync -av --delete ~/git/minorun365/my-claude-code-settings/.claude/rules/ ~/.claude/rules/
   rsync -av --delete ~/git/minorun365/my-claude-code-settings/.claude/skills/ ~/.claude/skills/
   cp ~/git/minorun365/my-claude-code-settings/.claude/CLAUDE.md ~/.claude/
   ```

## 注意事項

- 機密情報（APIキー等）が含まれていないか確認
- 新しいPCでPullする前に、既存のローカル設定をバックアップ推奨
- プッシュ前に必ずユーザーに確認を取る
