# MCP and OAuth troubleshooting

## MCP 設定・OAuth 共通トラブルシューティング

MCP の設定・OAuth 問題が発生したとき、必ずこの順で確認する：

1. **接続状態を確認**: `claude mcp list` でサーバーが `✓ Connected` か `✗ Failed to connect` かを把握
2. **競合プロセスを確認**: `ps aux | grep -E "mcp|uvx"` → 重複があれば kill
3. **設定の書き込み先**: 必ず `~/.claude.json`（`settings.json` や `settings.local.json` は MCP 設定の書き込み先としては無効）
4. **セッション再起動が必須**: MCP サーバーの追加・修復・再認証の後は **同一セッションでは反映されない**
5. **設定確認**: `jq '.mcpServers' ~/.claude.json`

**重要**: 上記を確認する前に `start_google_auth` などの OAuth ツールを複数回呼び出さない（state 競合が悪化する）。

### セッション内でツール一覧は固定される

Claude Code は **セッション起動時に MCP ツール一覧を確定** し、後から MCP サーバーを修復・再接続してもこのセッションでは新しいツールが使えない。

- `/mcp` の再接続では **ツール一覧は更新されない**（接続を張り直すだけ）
- ToolSearch でツール名が deferred tool list にすら出てこない場合は、ほぼ確実にセッション再起動が必要
- 修復が完了したら、ユーザーに **「Claude Code を再起動してください」** と明示する

### MCP サーバーが `Failed to connect` の最初のチェック

CLI バイナリ依存の MCP サーバー（workspace-mcp 等）は **バイナリ消失** で接続失敗することがある。`claude mcp list` で `✗ Failed to connect` を見たら、まず：

```bash
# 1. ~/.claude.json でコマンドパスを確認
jq -r '.mcpServers["<server-name>"].command' ~/.claude.json
# 2. そのパスにバイナリが存在するか確認
ls -la <command-path>
# 3. 無ければ再インストール（uv tool install <package> など）
```

OAuth エラーや credentials 問題は **その後** に確認する。バイナリが無ければ OAuth 以前に MCP サーバー自体が起動しない。

---

## HubSpot リモート MCP サーバー セットアップ（アーカイブ）

現行方針では、HubSpot を `~/.claude.json` の `mcpServers` へ直接登録しない。必要な場合は Claude Code Connect / コネクタとして扱う。

以下は、みのるんが明示的に HubSpot raw MCP / Remote MCP の検証を依頼した場合だけ参照する旧手順。

### 正しい設定値

| 項目 | 正しい値 | 間違いやすい値 |
|------|---------|--------------|
| URL | `https://mcp.hubspot.com/` | `https://mcp.hubspot.com/sse`（廃止）、`/mcp`（404） |
| 認証方式 | OAuth 2.1 + PKCE（MCP Auth App） | サービスキーのBearerトークン（×） |
| リダイレクトURL | `http://localhost:<port>/callback` | `/oauth/callback`（×） |
| clientSecret設定 | `claude mcp add --client-secret` + `MCP_CLIENT_SECRET` env | `.claude.json` 直書き（×） |

### セットアップ手順

```bash
# 1. HubSpot MCP Auth App を作成（ブラウザ）
# https://app.hubspot.com/mcp-auth-apps/<account_id>
# リダイレクトURL: http://localhost:3119/callback

# 2. Claude Code に追加
claude mcp remove hubspot -s user  # 既存があれば削除
MCP_CLIENT_SECRET=<client_secret> claude mcp add \
  -s user -t http \
  --client-id <client_id> \
  --client-secret \
  --callback-port 3119 \
  hubspot https://mcp.hubspot.com/

# 3. 再起動 → /mcp → Authenticate（ブラウザでOAuth認証）
# 4. 「Authentication successful, but server reconnection failed」→ 再起動（既知バグ）
# 5. 再起動後に自動接続される
```

### 正しいエンドポイントの特定方法（curl）

```bash
curl -s -o /dev/null -w "%{http_code}" https://mcp.hubspot.com/mcp  # 404 → 存在しない
curl -s -o /dev/null -w "%{http_code}" https://mcp.hubspot.com/     # 401 → 存在する！
```

### 現在の制限

- HubSpot リモート MCP は Public Beta で**読み取り専用**のみ
  - `get_crm_objects`, `search_crm_objects`, `get_properties` 等
  - 案件（Deal）**作成**はサービスキーを使った HubSpot API 直接呼び出しが必要

### 既知バグ

- Claude Code #10250: OAuth 認証成功後の自動再接続が失敗する
  - 対処: 認証後に Claude Code を再起動すると自動接続される
- `clientSecret` を `.claude.json` に直接書くと「missing or invalid client secret」エラー
  - 対処: `claude mcp add --client-secret` フラグを使う

---
