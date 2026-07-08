---
name: sync-claude-code-settings
description: Claude Codeの共通設定（rules、skills、agents、CLAUDE.md、mcpServers）をGitHubリポジトリと双方向同期する
user-invocable: true
model: sonnet
---

# Claude Code設定同期

Claude Codeの**共通設定のみ**をGitHubリポジトリと双方向同期します。
`/sync-dotfiles` から呼び出されることもあります。

## 同期対象（共通設定）

| ローカル | リポジトリ | 備考 |
|----------|------------|------|
| `~/.claude/rules/` | `claude/rules/` | トピック別ルールファイル |
| `~/.claude/skills/` | `claude/skills/` | ナレッジベース含む |
| `~/.claude/agents/` | `claude/agents/` | サブエージェント定義（model指定含む） |
| `~/.claude/CLAUDE.md` | `claude/CLAUDE.md` | Claude Code 固有設定（`@AGENTS.md` で共通ルールを読む） |
| `~/.claude/AGENTS.md` | `shared/common-agents.md` | Codex / Claude Code 共通ルール。repo 内 `claude/AGENTS.md` は置かない |
| `~/.claude.json` の `mcpServers` | `.claude.json` | 機密情報はマスク |
| `~/.claude/settings.json` の一部 | `claude/settings.json` | permissions（allow, deny, additionalDirectories）, model, language, outputStyle, voiceEnabled, spinnerVerbs, autoUpdatesChannel, attribution, effortLevel, hooks |
| `~/.claude/statusline.py` | `claude/statusline.py` | ステータスライン表示スクリプト |
| `~/.claude/hooks/` | `claude/hooks/` | PreToolUse等のフックスクリプト |

## mcpServers同期の注意事項

`mcpServers`セクションは以下のルールで同期：

1. **Push時**: ローカルの `mcpServers` をそのままリポジトリに反映（**明示削除モード**: ローカルにないサーバーはリポジトリからも削除される）。環境変数の値（トークン等）は `"<MASKED>"` に置換してエクスポート
2. **Pull時**: リポジトリにのみ存在する新規サーバーをローカルに追加（既存のローカル設定は機密情報を保持するため上書きしない）。1Passwordからシークレットを自動注入（`op read` でトークンを取得）

> ⚠️ **Push 前に必ず `git pull` で他Macの変更を取り込むこと**。Push は明示削除モードで動作するため、他Macで追加されたばかりのサーバーをローカルが知らないままPushすると、その追加が消える。

### 機密情報のマスク対象

以下のキーの値は自動的にマスクされる：
- `GITHUB_PERSONAL_ACCESS_TOKEN`
- `*_API_KEY`
- `*_TOKEN`
- `*_SECRET`

## 同期対象外（PC固有設定）

以下はPC固有のため**同期しない**：

- `~/.claude/settings.json` の一部 - `hooks` コマンドパスに絶対パスを使っている場合は手動修正が必要（`~` を使えば PC 間で互換）
- `~/.claude/projects/` - プロジェクト固有設定
- `~/.claude/plugins/` - プラグイン設定
- その他キャッシュ、履歴、デバッグログ等

## リポジトリパス

```
~/git/dotfiles/
```

## 実行手順

### Push（ローカル → リポジトリ）

1. **差分確認**
   ```bash
   diff -rq ~/.claude/rules/ ~/git/dotfiles/claude/rules/
   diff -rq ~/.claude/skills/ ~/git/dotfiles/claude/skills/
   diff -rq ~/.claude/agents/ ~/git/dotfiles/claude/agents/
   diff ~/.claude/CLAUDE.md ~/git/dotfiles/claude/CLAUDE.md
   diff ~/.claude/AGENTS.md ~/git/dotfiles/shared/common-agents.md
   diff ~/.claude/statusline.py ~/git/dotfiles/claude/statusline.py
   diff -rq ~/.claude/hooks/ ~/git/dotfiles/claude/hooks/
   diff <(jq '{permissions: {allow, deny, additionalDirectories}, model, language, outputStyle, voiceEnabled, spinnerVerbs, autoUpdatesChannel, attribution, effortLevel, hooks}' ~/.claude/settings.json) <(jq '{permissions: {allow, deny, additionalDirectories}, model, language, outputStyle, voiceEnabled, spinnerVerbs, autoUpdatesChannel, attribution, effortLevel, hooks}' ~/git/dotfiles/claude/settings.json 2>/dev/null || echo '{}')
   # mcpServers のキー差分（明示削除モードのため、リポジトリにのみ存在＝削除されるサーバーをここで把握する）
   diff <(jq -r '.mcpServers | keys[]' ~/.claude.json) <(jq -r '.mcpServers | keys[]' ~/git/dotfiles/.claude.json)
   ```

   > 💡 上記 `diff` で `>` 行（リポジトリにのみ存在）が出たら、それは **Push で削除されるサーバー**。意図した削除なら進める、意図しない削除（他Macで追加されたばかり）なら一度 Pull してから Push し直す。

2. **同期実行**
   ```bash
   rsync -av --delete ~/.claude/rules/ ~/git/dotfiles/claude/rules/
   rsync -av --delete ~/.claude/skills/ ~/git/dotfiles/claude/skills/
   rsync -av --delete ~/.claude/agents/ ~/git/dotfiles/claude/agents/
   cp ~/.claude/CLAUDE.md ~/git/dotfiles/claude/
   cp ~/.claude/AGENTS.md ~/git/dotfiles/shared/common-agents.md
   cp ~/.claude/statusline.py ~/git/dotfiles/claude/
   rsync -av --delete ~/.claude/hooks/ ~/git/dotfiles/claude/hooks/
   ```

3. **settings.json同期**（permissions の双方向マージ + その他フィールド上書き）
   ```bash
   # permissions.allow をローカル ∪ リポジトリでマージ（パスはローカルのユーザー名に統一）
   # permissions.deny はローカルを優先
   # additionalDirectories もパス変換して同期
   LOCAL_USER=$(whoami)
   jq -s --arg u "$LOCAL_USER" '
     .[0] as $repo |
     .[1] as $local |
     ($repo * {
       permissions: {
         allow: (
           ($local.permissions.allow +
            ($repo.permissions.allow | map(gsub("/Users/[^/]+/"; "/Users/\($u)/"))))
           | unique
         ),
         deny: ($local.permissions.deny // []),
         additionalDirectories: (
           ($local.permissions.additionalDirectories // []) +
           (($repo.permissions.additionalDirectories // []) | map(gsub("/Users/[^/]+/"; "/Users/\($u)/")))
         ) | unique
       },
       model: $local.model,
       language: $local.language,
       outputStyle: $local.outputStyle,
       voiceEnabled: $local.voiceEnabled,
       spinnerVerbs: $local.spinnerVerbs,
       autoUpdatesChannel: $local.autoUpdatesChannel,
       attribution: $local.attribution,
       effortLevel: $local.effortLevel,
       hooks: $local.hooks
     }) | with_entries(select(.value != null))
   ' ~/git/dotfiles/claude/settings.json \
     ~/.claude/settings.json > /tmp/settings.json && \
   mv /tmp/settings.json ~/git/dotfiles/claude/settings.json
   ```

4. **mcpServers同期**（明示削除モード + 機密情報マスク）
   ```bash
   # ローカルの mcpServers をそのままリポジトリに反映する（明示削除モード）
   # - ローカルにのみ存在するサーバー → リポジトリに追加
   # - 両方に存在するサーバー → ローカルの設定で上書き
   # - リポジトリにのみ存在するサーバー → 削除（ローカルで使わないと判断したMCPはリポジトリからも消す）
   # ⚠️ Push前に必ず git pull を実行して他Macの変更を取り込むこと
   jq -s '
     .[0] as $repo |
     (.[1].mcpServers // {}) as $local |
     ($repo | .mcpServers = $local) |
     .mcpServers |= walk(
       if type == "object" then
         with_entries(
           if (.key | test("TOKEN|KEY|SECRET"; "i")) and (.value | type == "string")
           then .value = "<MASKED>"
           else .
           end
         )
       else .
       end
     )
   ' ~/git/dotfiles/.claude.json ~/.claude.json > /tmp/.claude.json && \
   mv /tmp/.claude.json ~/git/dotfiles/.claude.json
   ```

5. **コミット・プッシュ**（自動実行）
   差分確認なしで自動コミット＆プッシュする（同期による変更は想定内のため）。

   > ⚠️ **`git add -A` は絶対に使わない**。`~/git/dotfiles/` を含むリポジトリで、`dotfiles/` はその中のサブディレクトリ（兄弟に `docs/` `notes/` `marp/` `qiita/` 等がある）。`git add -A` はカレントディレクトリではなく**リポジトリ全体**を対象にするため、`dotfiles/` 外の未コミット変更まで巻き込んでこの「設定同期」コミットに混入する（過去にこの事故が発生）。`cd` 済みなので `git add -- .`（＝カレント `dotfiles/` 以下のみ）を使うこと。
   ```bash
   cd ~/git/dotfiles
   git add -- .            # dotfiles/ 配下のみ。git add -A は禁止（モノレポの兄弟ディレクトリを巻き込む）
   git commit -m "設定同期"
   git push
   ```

### Pull（リポジトリ → ローカル）

1. **リポジトリを最新化**
   ```bash
   cd ~/git/dotfiles
   git pull
   ```

2. **差分確認**
   ```bash
   diff -rq ~/git/dotfiles/claude/rules/ ~/.claude/rules/
   diff -rq ~/git/dotfiles/claude/skills/ ~/.claude/skills/
   diff -rq ~/git/dotfiles/claude/agents/ ~/.claude/agents/
   diff ~/git/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md
   diff ~/git/dotfiles/shared/common-agents.md ~/.claude/AGENTS.md
   diff ~/git/dotfiles/claude/statusline.py ~/.claude/statusline.py
   diff -rq ~/git/dotfiles/claude/hooks/ ~/.claude/hooks/
   diff <(jq '{permissions: {allow, deny, additionalDirectories}, model, language, outputStyle, voiceEnabled, spinnerVerbs, autoUpdatesChannel, attribution, effortLevel, hooks}' ~/git/dotfiles/claude/settings.json 2>/dev/null || echo '{}') <(jq '{permissions: {allow, deny, additionalDirectories}, model, language, outputStyle, voiceEnabled, spinnerVerbs, autoUpdatesChannel, attribution, effortLevel, hooks}' ~/.claude/settings.json)
   ```

3. **同期実行**（ユーザー確認後）
   ```bash
   rsync -av --delete ~/git/dotfiles/claude/rules/ ~/.claude/rules/
   rsync -av --delete ~/git/dotfiles/claude/skills/ ~/.claude/skills/
   rsync -av --delete ~/git/dotfiles/claude/agents/ ~/.claude/agents/
   cp ~/git/dotfiles/claude/CLAUDE.md ~/.claude/
   cp ~/git/dotfiles/shared/common-agents.md ~/.claude/AGENTS.md
   cp ~/git/dotfiles/claude/statusline.py ~/.claude/
   rsync -av --delete ~/git/dotfiles/claude/hooks/ ~/.claude/hooks/
   ```

4. **settings.json適用**（permissions の双方向マージ + その他フィールド上書き）
   ```bash
   # permissions.allow をローカル ∪ リポジトリでマージ（パスはこのMacのユーザー名に統一）
   # additionalDirectories もパス変換して同期
   # hooks・statusLine はローカルを保持
   LOCAL_USER=$(whoami)
   jq -s --arg u "$LOCAL_USER" '
     .[0] as $local |
     .[1] as $repo |
     ($local * {
       permissions: {
         allow: (
           ($local.permissions.allow +
            ($repo.permissions.allow | map(gsub("/Users/[^/]+/"; "/Users/\($u)/"))))
           | unique
         ),
         deny: ($repo.permissions.deny // []),
         additionalDirectories: (
           ($local.permissions.additionalDirectories // []) +
           (($repo.permissions.additionalDirectories // []) | map(gsub("/Users/[^/]+/"; "/Users/\($u)/")))
         ) | unique
       },
       model: $repo.model,
       language: $repo.language,
       outputStyle: $repo.outputStyle,
       voiceEnabled: $repo.voiceEnabled,
       spinnerVerbs: $repo.spinnerVerbs,
       autoUpdatesChannel: $repo.autoUpdatesChannel,
       attribution: $repo.attribution,
       effortLevel: $repo.effortLevel,
       hooks: $repo.hooks
     }) | with_entries(select(.value != null))
   ' ~/.claude/settings.json \
     ~/git/dotfiles/claude/settings.json > /tmp/settings.json && \
   mv /tmp/settings.json ~/.claude/settings.json
   ```

5. **mcpServers適用**（半自動 + 手動）

   **5-1. 新規サーバーの構造をマージ（自動）**
   ```bash
   # リポジトリにのみ存在する新しいサーバーを追加（構造のみ、機密情報は <MASKED> のまま）
   jq -s '
     .[0] as $local |
     .[1] as $repo |
     $local * {
       mcpServers: (
         $local.mcpServers +
         ($repo.mcpServers | with_entries(
           select(
             (.key as $k | $local.mcpServers | has($k) | not)
           )
         ))
       )
     }
   ' ~/.claude.json ~/git/dotfiles/.claude.json > /tmp/.claude.json && \
   mv /tmp/.claude.json ~/.claude.json
   ```

   **5-2. パスの修正（Mac 2台対応）**
   ```bash
   # ユーザー名が異なる場合のパス修正（例: /Users/<旧ユーザー名> → /Users/<新ユーザー名>）
   # google-workspace の例:
   jq '.mcpServers["google-workspace"].command = "/Users/minorun365/.local/bin/workspace-mcp"' \
     ~/.claude.json > /tmp/.claude.json && \
   mv /tmp/.claude.json ~/.claude.json
   ```

   **5-3. 機密情報を1Passwordから注入**

   1Password（`my.1password.com`）の Private vault に保管している secret を `op` 経由で取得して、必要な MCP にだけ注入する。事前にデスクトップアプリの設定 → Developer で「Integrate with 1Password CLI」を有効化しておくこと（Touch ID で `op` が動作するようになる）。

   現行方針では、GitHub / Notion を raw MCP として再追加しない。コネクタで賄える SaaS は Claude Code Connect / コネクタを使う。

   ```bash
   # Google Workspace MCP 用 OAuth credentials
   mkdir -p ~/.config/google-workspace-mcp
   op read "op://Private/<アイテムID>/credentials" \
     --account my.1password.com \
     > ~/.config/google-workspace-mcp/gcp-oauth.keys.json
   chmod 600 ~/.config/google-workspace-mcp/gcp-oauth.keys.json
   CLIENT_SECRET=$(jq -r '.installed.client_secret' \
     ~/.config/google-workspace-mcp/gcp-oauth.keys.json)
   jq --arg s "$CLIENT_SECRET" \
     '.mcpServers["google-workspace"].env.GOOGLE_OAUTH_CLIENT_SECRET = $s' \
     ~/.claude.json > /tmp/.claude.json && mv /tmp/.claude.json ~/.claude.json
   ```

   **1Password に保管している secret アイテム一覧**

   | アイテム名 | アイテムID | フィールド | 用途 |
   |------------|-----------|------------|------|
   | `Google Workspace MCP OAuth (Claude Code)` | `<アイテムID>` | `credentials` | google-workspace MCP の OAuth credentials JSON 全文 |

   - 新しい secret を追加するときは、**vault に保管 → ID を記録 → このスキルに注入コマンドを追記** の順で運用する
   - GitHub / Notion 等の raw MCP secret 注入コマンドは追加しない。必要なら Connect / コネクタ側で認証する
   - アイテムタイトルに `(` `)` が含まれる場合や、フィールド名に日本語/記号が含まれる場合は Secret reference URL（`op://...`）が使えないので、`op item get <ID> --fields label="..." --reveal` で取得する
   - 詳細手順は `/kb-google-workspace-mcp` 等の関連スキル参照

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
- **hooks の同期**: スクリプト本体（`~/.claude/hooks/`）と `settings.json` 内の hooks 定義の両方が同期される。コマンドパスに `~` を使えば PC 間で互換性を保てる。絶対パスを使っている場合は Pull 後に手動修正が必要
