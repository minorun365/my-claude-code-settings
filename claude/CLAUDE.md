@AGENTS.md

# Claude Code 固有設定

AGENTS.md の共通ルールに加え、Claude Code 固有のツール運用を以下に記述する。
詳細ルールは `~/.claude/rules/*.md` に分離（ブラウザ操作の使い分けは `development.md` 参照）。

## SaaS 接続（Claude Code での実装）

SaaS 接続の原則（コネクタ優先・raw MCP 不使用・アカウント分離）は AGENTS.md が正。Claude Code 固有の補足のみ：

- `claude mcp list` では Connect / コネクタ由来の接続も `claude.ai <サービス名>` として表示される。これは `~/.claude.json` の raw `mcpServers` ではないため、コネクタ経由で繋ぐ SaaS はこの `claude.ai ...` 側にだけ出ていればよい

## MCP 構成（2026-06-21 整理後）

| MCP | 用途 |
|-----|------|
| `google-workspace` | Google Workspace 操作（`<メールアドレス>`） |
| `context7` | 公開ドキュメント検索 |
| `chrome-devtools` | AI agent Chrome profile（`[::1]:9222`）操作 |

削除済み：一部 SaaS 系（→ Connect / コネクタ側）、`strands` / `bedrock-agentcore-mcp-server`（→ `aws-agents` plugin でカバー）

## 設定同期

- `/sync-claude-code-settings` で `~/.claude/` と `dotfiles/claude/` を双方向同期。
- 設定変更後は同期 + `git push` で他 Mac に伝播させるまでが 1 セット。

## 参照すべきドキュメント

- Claude Code 詳細ルール: `~/.claude/rules/*.md`
- PC 固有設定: `~/.claude/projects/<ホスト固有パス>/CLAUDE.md`
- AWS アカウント情報: プロジェクトスコープの `memory/aws-accounts.md`
