---
name: kb-ts-aws
description: AWSトラブルシューティング。Cognito/Bedrock/Amplify/CDK/CloudWatch/S3 Vectors/aws login等
user-invocable: true
model: sonnet
---
# AWS トラブルシューティング

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提
- `references/cdk-cloudformation.md`: CFn/CDK Express mode、CDK Lambda ARM64 ImportModuleError、import.meta.url、CDK CLIとaws-cdk-libのバージョン不一致
- `references/bedrock-cognito-s3.md`: Cognito client_id mismatch、Bedrock Model Detector 重複通知、Bedrock AccessDenied（inference-profile）、S3 Vectors メタデータ制限
- `references/amplify.md`: Amplify sandbox / Console（CDK failed to publish assets、Dockerビルド）
- `references/aws-login.md`: aws login コマンド（v2.32.0〜）。sso loginとの使い分け、はまりどころ（signin権限不足、マルチセッション誤ログイン等）
- `references/debugging-cost.md`: デバッグTips（CloudWatch Logs/Insights）、MCP uvx バイナリ問題、Cost Explorer クレジット比較