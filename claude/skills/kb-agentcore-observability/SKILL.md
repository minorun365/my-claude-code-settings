---
name: kb-agentcore-observability
description: AgentCore の Observability ナレッジ。OpenTelemetry 必須4点セット（OTEL_EXPORTER設定・StrandsTelemetry・traceable デコレータ・Langfuse連携）、EMF メトリクス、Jaeger/コンソールエクスポーターでのトレース確認、トレースが出ない・繋がらない場合のデバッグ手順等
user-invocable: true
model: sonnet
---
# AgentCore Observability ナレッジ

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提
- `references/otel-setup.md`: Observability（トレース）セットアップ、OTELログ形式
- `references/metrics-emf.md`: EMF（Embedded Metric Format）メトリクス
- `references/tracing.md`: トレースの確認、ローカル開発のコンソールエクスポーター、StrandsTelemetry API
- `references/langfuse.md`: Langfuse連携（サードパーティOTEL送信）
- `references/calc-and-pdf.md`: LLMにやらせてはいけない計算、FPDF2でPDF生成（日本語対応）
- `references/troubleshooting.md`: トラブルシューティング、関連スキル、参考リンク
