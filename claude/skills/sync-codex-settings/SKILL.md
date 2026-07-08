---
name: sync-codex-settings
description: Codexの共通設定（AGENTS.md、config.toml、rules、agents、skills、skills-archive）をGitHubリポジトリと双方向同期する
user-invocable: true
model: sonnet
---

# Codex設定同期

Codex の **共通設定のみ** を GitHub リポジトリと双方向同期します。
`/sync-dotfiles` から呼び出されることもあります。

## 同期対象（共通設定）

| ローカル | リポジトリ | 備考 |
|----------|------------|------|
| `~/.codex/AGENTS.md` | `shared/common-agents.md` + `codex/AGENTS.codex.md` | 生成されるグローバル作業ガイド |
| `~/.codex/config.toml` | `codex/config.toml` | model / plugins / MCP Server 設定 |
| `~/.codex/agents/` | `codex/agents/` | custom agents |
| `~/.codex/skills/` | `codex/skills/` | `.system` は除外 |
| `~/.codex/rules/` | `codex/rules/` | 承認 prefix ルール |
| `~/.codex/skills-archive/` | `codex/skills-archive/` | 低頻度スキルの退避先 |

## 同期対象外（PC固有設定）

以下は PC 固有またはキャッシュのため **同期しない**：

- `~/.codex/auth.json`
- `~/.codex/plugins/`
- `~/.codex/vendor_imports/`
- `~/.codex/memories/`
- `~/.codex/sessions/`
- `~/.codex/shell_snapshots/`
- `~/.codex/*.sqlite*`
- `~/.codex/.codex-global-state.json`
- `~/.codex/models_cache.json`
- `~/.codex/tmp/`
- `~/.codex/cache/`
- `~/.codex/.tmp/`
- `~/.codex/skills/.system/` - Codex 同梱スキル

補足: `~/.codex/skills-archive/` は同期対象だが、自動発動対象外の退避先として扱う。

## リポジトリパス

```bash
~/git/dotfiles/
```

## 実行手順

### Push（ローカル → リポジトリ）

1. **差分確認**
   ```bash
   # ~/.codex/AGENTS.md は生成物。共通ルールは shared/common-agents.md、
   # Codex 固有差分は codex/AGENTS.codex.md を編集する。
   diff <(
     echo '# Codex グローバル作業ガイド'
     echo
     echo '<!-- Generated from dotfiles/shared/common-agents.md and dotfiles/codex/AGENTS.codex.md. Do not edit ~/.codex/AGENTS.md directly. -->'
     echo
     cat ~/git/dotfiles/shared/common-agents.md
     echo
     cat ~/git/dotfiles/codex/AGENTS.codex.md
   ) ~/.codex/AGENTS.md
   diff ~/.codex/config.toml ~/git/dotfiles/codex/config.toml
   diff -rq ~/.codex/agents/ ~/git/dotfiles/codex/agents/
   diff -rq ~/.codex/skills/ ~/git/dotfiles/codex/skills/
   diff -rq ~/.codex/rules/ ~/git/dotfiles/codex/rules/
   diff -rq ~/.codex/skills-archive/ ~/git/dotfiles/codex/skills-archive/
   ```
   - `.system` 配下の差分は無視してよい
   - `~/.codex/AGENTS.md` の差分は repo へ push せず、必要な内容を `shared/common-agents.md` または `codex/AGENTS.codex.md` へ反映する

2. **同期実行**
   ```bash
   cd ~/git/dotfiles
   ./scripts/sync-codex-settings.sh push
   ```

3. **差分確認**
   ```bash
   cd ~/git/dotfiles
   git status
   git diff
   ```

4. **コミット・プッシュ**（ユーザー確認後）

   > ⚠️ **`git add -A` は絶対に使わない**。`~/git/dotfiles/` を含むリポジトリで、`dotfiles/` はその中のサブディレクトリ（兄弟に `docs/` `notes/` `marp/` `qiita/` 等がある）。`git add -A` は**リポジトリ全体**を対象にするため、`dotfiles/` 外の未コミット変更まで巻き込む（過去にこの事故が発生）。`cd` 済みなので `git add -- .`（＝カレント `dotfiles/` 以下のみ）を使うこと。
   ```bash
   cd ~/git/dotfiles
   git add -- .            # dotfiles/ 配下のみ。git add -A は禁止（モノレポの兄弟ディレクトリを巻き込む）
   git commit -m "Codex設定同期"
   git push
   ```

### Pull（リポジトリ → ローカル）

1. **リポジトリを最新化**
   ```bash
   cd ~/git/dotfiles
   git pull
   ```

2. **同期実行**
   ```bash
   cd ~/git/dotfiles
   ./scripts/sync-codex-settings.sh pull
   ```

3. **反映確認**
   ```bash
   # ~/.codex/AGENTS.md は shared/common-agents.md + codex/AGENTS.codex.md から生成される
   diff <(
     echo '# Codex グローバル作業ガイド'
     echo
     echo '<!-- Generated from dotfiles/shared/common-agents.md and dotfiles/codex/AGENTS.codex.md. Do not edit ~/.codex/AGENTS.md directly. -->'
     echo
     cat ~/git/dotfiles/shared/common-agents.md
     echo
     cat ~/git/dotfiles/codex/AGENTS.codex.md
   ) ~/.codex/AGENTS.md
   diff ~/.codex/config.toml ~/git/dotfiles/codex/config.toml
   ```

4. **必要なら Codex を再起動**
   - `config.toml` や MCP Server を変更した場合は Codex 再起動を案内する

## Codex 設定で注意する点

- MCP Server は `~/.codex/config.toml` の `[mcp_servers.<name>]` で管理する
- `~/.codex/AGENTS.md` は生成物。共通ルールは `shared/common-agents.md`、Codex 固有差分は `codex/AGENTS.codex.md` を編集する
- `dotfiles/codex/AGENTS.md` は repo-scoped 指示として重複読み込みされやすいため置かない
- 機密値は repo に埋め込まず、環境変数から渡す
- 現在の想定環境変数:
  - `GITHUB_PERSONAL_ACCESS_TOKEN`
  - `GOOGLE_OAUTH_CLIENT_SECRET`
- `google-workspace` の `command` は端末ごとのホームパス差分に注意する。Codex では Google アカウント用 MCP として扱う
- SaaS は Codex App / plugin を入口にし、raw MCP 直登録は避ける
- `.system` スキルは Codex 同梱なので repo にコピーしない

## 自動実行ルール

このスキルでは以下のルールで判断する：

- **自動で進めてよい場合**:
  - Push/Pull 方向が明確
  - 差分が Codex 設定の同期として自然
- **ユーザーに確認する場合**:
  - Push/Pull どちらか判断できない
  - ローカルとリポジトリの両方に別の変更がありそう
  - `config.toml` に意図不明な削除がある
  - 端末依存パスの変更が必要

## 注意事項

- 新しい PC で Pull する前に既存の `~/.codex/` をバックアップ推奨
- `scripts/sync-codex-settings.sh pull` は `AGENTS.md` と `config.toml` をバックアップしてから上書きする
- スキル実行後に Codex の MCP が反映されない場合は再起動で解決することが多い
