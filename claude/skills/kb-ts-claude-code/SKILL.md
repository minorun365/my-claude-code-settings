---
name: kb-ts-claude-code
description: Claude Code 設定・トラブルシューティング。Chrome DevTools MCP セットアップ、permissions の Bash 連結問題、GHE push 403、MCP OAuth エラー、HubSpot MCP 設定、CLAUDE.md/rules/skills の責務分離、skill frontmatter、OSS コントリビューション等
user-invocable: true
model: sonnet
---
# Claude Code 設定・トラブルシューティング

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提
- `references/permissions-settings.md`: permissions、CLAUDE.md、settings、rules、skills/agents設計
- `references/browser-forms.md`: Chrome DevTools MCP、フォーム操作、a11y外要素、大量フォーム自動化
- `references/git-github-oss.md`: GHE 403、gh複数アカウント、OSSコントリビューション
- `references/mcp-oauth.md`: MCP接続、OAuth、HubSpot MCP
- `references/agent-editing.md`: サブエージェント報告の検証、Edit/Rename後の注意
