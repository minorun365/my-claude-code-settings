# AWS関連のナレッジ

プロジェクト横断で得たAWSの学びを記録する。

## Bedrock

- クロスリージョン推論を使う場合、モデルIDのプレフィックスは `us.` になる
- Bedrock AgentCoreはus-east-1とus-west-2で利用可能

## Lambda

- （学びを追記）

## IAM

### Bedrockモデル呼び出し権限

クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する場合、以下の両方のリソースへの権限が必要：

```
arn:aws:bedrock:*::foundation-model/*       # 基盤モデル
arn:aws:bedrock:*:*:inference-profile/*     # 推論プロファイル
```

`foundation-model/*` だけでは `AccessDeniedException` が発生する。

## Cognito

### IDトークン vs アクセストークン

| トークン | 用途 | クライアントIDの格納先 |
|---------|------|---------------------|
| IDトークン | ユーザー情報（名前、メールなど）取得 | `aud` クレーム |
| アクセストークン | APIへのアクセス認可 | `client_id` クレーム |

API認証で `client_id` を検証する場合は**アクセストークン**を使用する。

## その他

- （学びを追記）
