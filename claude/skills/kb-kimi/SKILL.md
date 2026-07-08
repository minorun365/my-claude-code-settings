---
name: kb-kimi
description: Kimi K2（Moonshot AI）特有の問題とワークアラウンド。Claudeモデルとの差異、リトライ処理等
user-invocable: true
model: sonnet
---
# Kimi K2 ナレッジ

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・基本情報（モデルID、Claudeとの差異、BedrockModel設定の注意）
- `references/events.md`: イベント処理（reasoningイベント等）
- `references/troubleshooting.md`: トラブルシューティング（reasoningText内ツール呼び出し、JSON引数のマークダウン、ツール名破損とリトライ、think タグ混入、Web検索後スライド未生成 等）
- `references/design-patterns.md`: 設計パターン（モデル切り替え対応、Kimiのみリトライ）、参考リンク
