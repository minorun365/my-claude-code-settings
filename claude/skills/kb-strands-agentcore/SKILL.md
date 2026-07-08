---
name: kb-strands-agentcore
description: Strands Agents フレームワークのナレッジ。Agent作成、ツール定義、イベント処理、会話履歴管理等（CDKは /kb-agentcore-cdk、Observabilityは /kb-agentcore-observability、Identity認証は /kb-agentcore-identity）
user-invocable: true
model: sonnet
---
# Strands Agents ナレッジ

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提、基本情報、インストール
- `references/agent-and-events.md`: Agent作成、実行方法、イベントタイプ
- `references/tools.md`: ツールの定義（@toolデコレータ、非同期、ToolContext等）
- `references/conversation.md`: 会話履歴の管理（ConversationManager、セッション永続化）
- `references/agentcore-integration.md`: Bedrock AgentCore との統合、Bedrockプロンプトキャッシュが突然停止する問題
- `references/troubleshooting.md`: トラブルシューティング、関連スキル、参考リンク
