---
name: sync-claude-code-settings
description: Claude Codeの共通設定（skills、CLAUDE.md、mcpServers）をGitHubリポジトリと双方向同期する
user-invocable: true
---

# Claude Code設定同期

Claude Codeの**共通設定のみ**をGitHubリポジトリと双方向同期します。
`/sync-dotfiles` から呼び出されることもあります。

## 同期対象（共通設定）

| ローカル | リポジトリ | 備考 |
|----------|------------|------|
| `~/.claude/skills/` | `claude/skills/` | ナレッジベース含む |
| `~/.claude/CLAUDE.md` | `claude/CLAUDE.md` | |
| `~/.claude.json` の `mcpServers` | `.claude.json` | 機密情報はマスク |
| `~/.claude/settings.json` の一部 | `claude/settings.json` | permissions, spinnerVerbs, language |

## mcpServers同期の注意事項

`mcpServers`セクションは以下のルールで同期：

1. **Push時**: 環境変数の値（トークン等）を `"<MASKED>"` に置換してエクスポート
2. **Pull時**: リポジトリのJSONを参考に手動で設定（機密情報は各自で設定）

### 機密情報のマスク対象

以下のキーの値は自動的にマスクされる：
- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `*_API_KEY`
- `*_TOKEN`
- `*_SECRET`

## 同期対象外（PC固有設定）

以下はPC固有のため**同期しない**：

- `~/.claude/settings.json` の一部 - hooks、statusLine（PC固有パスやOS依存）
- `~/.claude/hooks/` - フックスクリプト
- `~/.claude/projects/` - プロジェクト固有設定
- `~/.claude/plugins/` - プラグイン設定
- `~/.claude/rules/` - **廃止済み（skillsに移行）**
- その他キャッシュ、履歴、デバッグログ等

## リポジトリパス

```
~/git/minorun365/dotfiles/
```

## 実行手順

### Push（ローカル → リポジトリ）

1. **差分確認**
   ```bash
   diff -rq ~/.claude/skills/ ~/git/minorun365/dotfiles/claude/skills/
   diff ~/.claude/CLAUDE.md ~/git/minorun365/dotfiles/claude/CLAUDE.md
   diff <(jq '{permissions, spinnerVerbs, language}' ~/.claude/settings.json) <(jq '{permissions, spinnerVerbs, language}' ~/git/minorun365/dotfiles/claude/settings.json 2>/dev/null || echo '{}')
   ```

2. **同期実行**
   ```bash
   rsync -av --delete ~/.claude/skills/ ~/git/minorun365/dotfiles/claude/skills/
   cp ~/.claude/CLAUDE.md ~/git/minorun365/dotfiles/claude/
   ```

3. **settings.json同期**（permissions, spinnerVerbs, language）
   ```bash
   # リポジトリの既存設定をベースに、ローカルのspinnerVerbs/languageで更新
   jq -s '.[0] * {permissions: .[1].permissions, spinnerVerbs: .[1].spinnerVerbs, language: .[1].language}' \
     ~/git/minorun365/dotfiles/claude/settings.json \
     ~/.claude/settings.json > /tmp/settings.json && \
   mv /tmp/settings.json ~/git/minorun365/dotfiles/claude/settings.json
   ```

4. **mcpServers同期**（機密情報をマスクしてエクスポート）
   ```bash
   # jqで mcpServers を抽出し、機密情報をマスク
   jq '{mcpServers: .mcpServers | walk(
     if type == "object" then
       with_entries(
         if (.key | test("TOKEN|KEY|SECRET"; "i")) and (.value | type == "string")
         then .value = "<MASKED>"
         else .
         end
       )
     else .
     end
   )}' ~/.claude.json > ~/git/minorun365/dotfiles/.claude.json
   ```

5. **コミット・プッシュ**（ユーザー確認後）
   ```bash
   cd ~/git/minorun365/dotfiles
   git add -A
   git status
   git commit -m "設定同期"
   git push
   ```

### Pull（リポジトリ → ローカル）

1. **リポジトリを最新化**
   ```bash
   cd ~/git/minorun365/dotfiles
   git pull
   ```

2. **差分確認**
   ```bash
   diff -rq ~/git/minorun365/dotfiles/claude/skills/ ~/.claude/skills/
   diff ~/git/minorun365/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
   diff <(jq '{permissions, spinnerVerbs, language}' ~/git/minorun365/dotfiles/claude/settings.json 2>/dev/null || echo '{}') <(jq '{permissions, spinnerVerbs, language}' ~/.claude/settings.json)
   ```

3. **同期実行**（ユーザー確認後）
   ```bash
   rsync -av --delete ~/git/minorun365/dotfiles/claude/skills/ ~/.claude/skills/
   cp ~/git/minorun365/dotfiles/claude/CLAUDE.md ~/.claude/
   ```

4. **settings.json適用**（permissions, spinnerVerbs, language）
   ```bash
   # ローカルの既存設定をベースに、リポジトリのspinnerVerbs/languageで更新
   jq -s '.[0] * {permissions: .[1].permissions, spinnerVerbs: .[1].spinnerVerbs, language: .[1].language}' \
     ~/.claude/settings.json \
     ~/git/minorun365/dotfiles/claude/settings.json > /tmp/settings.json && \
   mv /tmp/settings.json ~/.claude/settings.json
   ```

5. **mcpServers適用**（手動）
   - `.claude.json` を参照して `~/.claude.json` の `mcpServers` を更新
   - `<MASKED>` 部分は各自の認証情報に置き換える

## 自動実行ルール

このスキルのコマンドは自動承認されている。以下のルールで判断する：

- **自動で進めてよい場合**: Push/Pull方向が明確で、差分内容が想定通りの場合
- **ユーザーに確認する場合**:
  - Push/Pull どちらの方向で同期すべきか判断がつかない場合
  - ローカルとリポジトリの両方に異なる変更がある（コンフリクトの可能性）場合
  - 差分に意図不明な変更や削除が含まれる場合
  - 機密情報（APIキー等）がマスクされずに残っている場合

## 注意事項

- 新しいPCでPullする前に、既存のローカル設定をバックアップ推奨
