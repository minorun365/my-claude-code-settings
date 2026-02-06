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

非同期Lambda呼び出しの場合、replyTokenが30秒で失効するため **Push Messageのみ使用** する。Push Messageは月の無料枠（コミュニケーションプラン: 200通）があるため、SSEストリーミングで細かく送信すると枠を使い切りやすい。

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

## Push Message のレート制限と月間上限

### レート制限（秒単位）

| エンドポイント | レート制限 |
|---|---|
| Push Message | 2,000 req/s（チャネル単位） |
| Loading Animation | 100 req/s |
| Multicast | 200 req/s |

- レート制限はチャネル単位で適用
- 429レスポンスに `Retry-After` ヘッダーは含まれない
- LINE公式は429を「リトライすべきでない4xx」に分類 → リトライではなくスロットリング（頻度低減）が正しい対処

### 月間メッセージ上限

無料プラン（コミュニケーションプラン）は **月200通** が上限。超過すると429エラー:
```json
{"message": "You have reached your monthly limit."}
```

SSEストリーミングで `contentBlockStop` ごとにPush Messageを送ると、1回の対話で多数の通数を消費してしまう。通数節約のために最終ブロックのみ送信する方式を推奨。

---

## SSE → Push Message 変換パターン

AIエージェント（AgentCore等）のSSEストリーミングをLINE Push Messageに変換するパターン。

### 方式A: 最終ブロックのみ送信（通数節約・推奨）

ツールステータスだけリアルタイム送信し、テキストは最終ブロックのみ1通で送信する方式。月間メッセージ上限の節約に有効。

```python
text_buffer = ""
last_text_block = ""

# contentBlockDelta → バッファに蓄積
text_buffer += text

# contentBlockStop → 最終ブロック候補として保持（送信しない）
last_text_block = text_buffer.strip()
text_buffer = ""

# ツール開始 → バッファを破棄（途中応答は不要）してステータス送信
text_buffer = ""
throttled_send(status_text)

# SSE完了後 → 最終ブロックのみ送信
send_push_message(reply_to, last_text_block[:5000])
```

ツールを使わない場合（AIからの質問返し等）も、唯一のテキストブロックが最終ブロックとなるため正常に動作する。

### 方式B: contentBlockStop ごとに送信（ストリーミング体験重視）

```python
text_buffer = ""

def flush_text_buffer():
    nonlocal text_buffer
    if text_buffer.strip():
        send_push_message(reply_to, text_buffer.strip()[:5000])
        text_buffer = ""
```

通数を多く消費するため、有料プランでのみ推奨。

### SSEイベントとLINEメッセージの対応

```
SSEイベント                              方式A                    方式B
──────────────────────────────────    ─────────────────────    ─────────────────────
contentBlockDelta(text: "...")      → バッファに蓄積          → バッファに蓄積
contentBlockStop                    → last_text_blockに保持   → flush → Push Message
contentBlockStart(toolUse: name)    → ステータス送信          → flush + ステータス送信
[DONE]                              → last_text_block送信     → 処理完了
```

### 送信スロットリング

429エラー防止のため、Push Message送信に最低1秒の間隔を設ける:

```python
import time

last_send_time = 0.0
MIN_SEND_INTERVAL = 1.0

def throttled_send(text: str) -> None:
    nonlocal last_send_time
    elapsed = time.time() - last_send_time
    if elapsed < MIN_SEND_INTERVAL:
        time.sleep(MIN_SEND_INTERVAL - elapsed)
    send_push_message(reply_to, text)
    last_send_time = time.time()
```

非同期Lambda呼び出しのため、`time.sleep`でLambda実行時間が伸びてもLINEのレスポンスには影響しない。

### UXのコツ

- ユーザーからメッセージを受けたら、エージェント呼び出し前に「考えています...」を即座に返す（体感レスポンス向上）
- ツール使用中は日本語のステータスメッセージを送る（何をしているか可視化）
- Markdownは使わない（LINEではレンダリングされない）
  - NG: `**太字**`、`# 見出し`、`[リンク](URL)`
  - OK: 「・」箇条書き、【】強調、改行区切り

---

## LINE ユーザーIDの注意

LINE のユーザーIDは `U` + 32桁の英数字（例: `U56b15391befe93872af9cd62f40fb7aa`）。LINE の表示名（ニックネーム）や LINE ID（検索用ID）とは全く別物。

ユーザーIDの確認方法:
- Lambda の CloudWatch Logs に `User Uxxxxxxxx` の形式で出力される
- 各ユーザーに1回メッセージを送ってもらい、ログからIDを収集する

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
