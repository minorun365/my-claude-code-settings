---
name: kb-google-workspace-mcp
description: Google Workspace 用 MCP サーバーのナレッジ。OAuth設定、ツール運用、トラブルシューティング等
user-invocable: true
model: sonnet
---
# Google Workspace MCP ナレッジ

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提
- `references/setup-oauth.md`: MCPサーバー選定、OAuth設定、セキュリティ、スコープ
- `references/troubleshooting.md`: MCPツール不可、OAuthエラー、Sheets範囲、port競合など
- `references/gas-and-workspace-tools.md`: clasp、GAS、会議調整、Slides取得、参考リンク
