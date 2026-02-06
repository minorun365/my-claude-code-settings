---
name: kb-line
description: LINE Bot開発のナレッジ。Messaging API、Webhook、署名検証、Push Message、グループチャット対応、SSEストリーミング連携等
user-invocable: true
---

# LINE Bot 開発ナレッジ

LINE Messaging APIを使ったチャットボット開発のベストプラクティス集。

## 基本アーキテクチャ

### API Gateway + Lambda（非同期呼び出し）パターン

```
LINE User → API Gateway (REST) → Lambda (非同期起動)
                                    ├── LINE署名検証
                                    ├── ビジネスロジック / AI処理
                                    └── Push Message で返信
```

LINE Webhookは3秒以内のレスポンスを要求するため、API Gatewayで即座に200を返却し、Lambdaを非同期で起動する。

```typescript
// CDK: API Gateway → Lambda 非同期呼び出し統合
const lambdaIntegration = new apigateway.AwsIntegration({
  service: "lambda",
  path: `2015-03-31/functions/${webhookFn.functionArn}/invocations`,
  integrationHttpMethod: "POST",
  options: {
    credentialsRole: apiGatewayRole,
    requestParameters: {
      "integration.request.header.X-Amz-Invocation-Type": "'Event'",  // 非同期
    },
    requestTemplates: {
      "application/json": `{
  "body": "$util.escapeJavaScript($input.body)",
  "signature": "$input.params('x-line-signature')"
}`,
    },
    integrationResponses: [
      {
        statusCode: "200",
        responseTemplates: {
          "application/json": '{"message": "accepted"}',
        },
      },
    ],
  },
});
```

### Reply Message vs Push Message

| 方式 | 制限 | 用途 |
|------|------|------|
| Reply Message | replyToken必須（30秒有効）、無料 | 同期処理向け |
| Push Message | user_id/group_id指定、月200通（無料枠） | 非同期処理向け |

非同期Lambda呼び出しの場合、replyTokenが30秒で失効するため **Push Messageのみ使用** する。

---

## LINE署名検証

### VTLテンプレートでのraw body受け渡し

API Gatewayの統合リクエストでLINE Webhookのbodyをそのまま渡す際の注意点。

```
# NG: パース済みJSONを返すため、署名検証に使えない
$input.json('$')

# OK: raw bodyを文字列として渡す
$util.escapeJavaScript($input.body)
```

Lambda側ではbodyを文字列として受け取る:
```python
body_str = event.get("body", "")
signature = event.get("signature", "")

# LINE署名検証
events = parser.parse(body_str, signature)
```

---

## LINE Bot SDK v3 (Python)

### インストール

```
# requirements.txt
line-bot-sdk
```

### 基本的な使い方

```python
from linebot.v3 import WebhookParser
from linebot.v3.exceptions import InvalidSignatureError
from linebot.v3.messaging import (
    ApiClient,
    Configuration,
    MessagingApi,
    PushMessageRequest,
    TextMessage,
)
from linebot.v3.webhooks import MessageEvent, TextMessageContent

# 初期化
parser = WebhookParser(LINE_CHANNEL_SECRET)
line_config = Configuration(access_token=LINE_CHANNEL_ACCESS_TOKEN)

# Push Message送信
def send_push_message(reply_to: str, text: str) -> None:
    if not text.strip():
        return
    with ApiClient(line_config) as api_client:
        api = MessagingApi(api_client)
        api.push_message(
            PushMessageRequest(
                to=reply_to,
                messages=[TextMessage(text=text.strip())],
            )
        )
```

### テキスト上限

LINE Push Messageのテキスト上限は **5000文字**。長いメッセージは切り詰める:
```python
send_push_message(reply_to, text.strip()[:5000])
```

---

## グループチャット対応

### メンション検出

グループチャットではBot宛メンション時のみ処理する:

```python
def _is_bot_mentioned(message: TextMessageContent) -> bool:
    if not message.mention:
        return False
    return any(
        getattr(m, "is_self", False) for m in message.mention.mentionees
    )
```

### メンション文字列の除去

`@Bot名` をメッセージテキストから除去してからビジネスロジックに渡す:

```python
def _strip_bot_mention(message: TextMessageContent) -> str:
    text = message.text
    if not message.mention:
        return text.strip()
    # index が大きい方から除去（位置ずれ防止）
    mentionees = sorted(
        (m for m in message.mention.mentionees if getattr(m, "is_self", False)),
        key=lambda m: m.index,
        reverse=True,
    )
    for m in mentionees:
        text = text[:m.index] + text[m.index + m.length :]
    return text.strip()
```

### 送信先の判定

```python
source = line_event.source
is_group_chat = source.type in ("group", "room")

# 送信先: グループならgroup_id/room_id、1対1ならuser_id
reply_to = (
    getattr(source, "group_id", None)
    or getattr(source, "room_id", None)
    or source.user_id
)
```

### LINE Official Accountの設定

グループチャットで使うには:
1. LINE Official Account Manager → 設定 → アカウント設定
2. 「グループトーク・複数人トークへの参加を許可する」をオン
3. グループにBotを招待

---

## SSE → Push Message 変換パターン

AIエージェント（AgentCore等）のSSEストリーミングをリアルタイムにLINE Push Messageに変換するパターン。

### テキストバッファリング戦略

```python
TOOL_STATUS_MAP = {
    "http_request": "カレンダーを確認しています...",
    "current_time": "現在時刻を確認しています...",
    "web_search": "ウェブ検索しています...",
}

text_buffer = ""

def flush_text_buffer():
    nonlocal text_buffer
    if text_buffer.strip():
        send_push_message(reply_to, text_buffer.strip()[:5000])
        text_buffer = ""
```

### SSEイベントとLINEメッセージの対応

```
SSEイベント                              LINEに送るPush Message
──────────────────────────────────    ──────────────────────────
contentBlockDelta(text: "...")      → テキストバッファに蓄積
contentBlockStop                    → バッファをflush → Push Message送信
contentBlockStart(toolUse: name)    → 「○○しています...」ステータス送信
[DONE]                              → 処理完了
```

### UXのコツ

- ユーザーからメッセージを受けたら、エージェント呼び出し前に「考えています...」を即座に返す（体感レスポンス向上）
- ツール使用中は日本語のステータスメッセージを送る（何をしているか可視化）
- Markdownは使わない（LINEではレンダリングされない）
  - NG: `**太字**`、`# 見出し`、`[リンク](URL)`
  - OK: 「・」箇条書き、【】強調、改行区切り

---

## 環境変数

| 変数名 | 用途 |
|--------|------|
| `LINE_CHANNEL_SECRET` | Webhook署名検証 |
| `LINE_CHANNEL_ACCESS_TOKEN` | Push Message送信 |

### LINE Channel セットアップ手順

1. [LINE Official Account Manager](https://manager.line.biz/) でアカウント作成
2. Messaging API を有効化
3. [LINE Developers Console](https://developers.line.biz/) で Channel Secret / Channel Access Token を取得
4. CDKデプロイ後、Webhook URLを設定
5. Auto-reply messages をオフにする

---

## 参考リンク

- [LINE Messaging API ドキュメント](https://developers.line.biz/ja/docs/messaging-api/)
- [line-bot-sdk-python GitHub](https://github.com/line/line-bot-sdk-python)
- [LINE Official Account Manager](https://manager.line.biz/)
- [LINE Developers Console](https://developers.line.biz/)
