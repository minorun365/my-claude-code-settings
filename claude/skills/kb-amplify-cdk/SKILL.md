---
name: kb-amplify-cdk
description: Amplify Gen2 + CDK のナレッジ。sandbox管理、本番デプロイ、Hotswap等
user-invocable: true
model: sonnet
---
# Amplify Gen2 + CDK ナレッジ

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提
- `references/gen2-basics.md`: 基本構造、カスタムCDK、カスタム出力、環境分岐
- `references/sandbox-production.md`: sandbox、本番環境、Hotswap、sandbox管理、deploy-time-build
- `references/frontend-storage-cognito.md`: 開発時トラブル、CloudFront/S3、Cognito検証ユーザー、Migration Trigger
- `references/domains-agentcore-errors.md`: カスタムドメイン、AgentCore WebSocket、よくあるエラー
