---
name: kb-bidi-agent
description: BidiAgent（双方向ストリーミング / 音声対話）のナレッジ。Nova Sonic、WebSocket、カスタムI/O等
user-invocable: true
---

# BidiAgent（双方向ストリーミング / 音声対話）

Strands Agents の BidiAgent を使った双方向ストリーミング・音声対話の学びを記録する。
基本的な Strands Agents / AgentCore のナレッジは `/kb-strands-agentcore` を参照。フロントエンドの Web Audio / WebSocket 実装は `/kb-web-audio` を参照。

## 基本情報

- `strands-agents[bidi]` で追加インストール（実験的機能）
- Python 3.12+ 必須
- `from strands.experimental.bidi import BidiAgent`
- `from strands.experimental.bidi.models.nova_sonic import BidiNovaSonicModel`
- 対応モデル: Amazon Nova Sonic v1 (`amazon.nova-sonic-v1:0`) / v2 (`amazon.nova-2-sonic-v1:0`)
- Nova 2 Sonic は音声品質向上・ポリグロット対応・ターン検知制御（`turn_detection`）等が追加
- `turn_detection` は v2 専用（v1 で使うと ValueError）
- `AudioSampleRate` の型定義: `Literal[16000, 24000, 48000]`（v2 の推奨出力は 24kHz）
- 対応リージョン: `us-east-1`, `eu-north-1`, `ap-northeast-1`

## BidiNovaSonicModel の初期化

```python
import boto3
from strands.experimental.bidi.models.nova_sonic import BidiNovaSonicModel

session = boto3.Session(profile_name="sandbox", region_name="us-east-1")

model = BidiNovaSonicModel(
    model_id="amazon.nova-2-sonic-v1:0",  # v2推奨
    provider_config={
        "audio": {
            "input_rate": 16000,
            "output_rate": 24000,   # Nova 2 Sonic は 24kHz 推奨
            "voice": "tiffany",
        },
    },
    client_config={"boto_session": session},
)
```

### provider_config["audio"] のキー名に注意

SDK が認識するキーは **`input_rate`** / **`output_rate`** のみ。`input_sample_rate` / `output_sample_rate` は**無視される**（dict merge で未知キーとして残るが、SDK は参照しない）。間違ったキー名を使うと **デフォルトの 16kHz** がそのまま使われ、フロントエンドとのサンプルレート不一致で音声が早送りや遅再生になる。

```python
# NG: SDK が認識しないキー名（デフォルト 16kHz が使われる）
"audio": {
    "input_sample_rate": 16000,
    "output_sample_rate": 24000,
}

# OK: SDK が認識するキー名
"audio": {
    "input_rate": 16000,
    "output_rate": 24000,
}
```

SDK 内部の `_resolve_provider_config` メソッドが `default_audio` dict と `config.get("audio", {})` を merge する仕組みのため、正しいキー名でないとデフォルト値が上書きされない。

### client_config の注意点

`boto_session` と `region` は **同時に指定できない**（ValueError）。リージョンは `boto3.Session(region_name=...)` に含める。

```python
# NG: ValueError
client_config={"region": "us-east-1", "boto_session": session}

# OK: boto_session にリージョンを含める
session = boto3.Session(region_name="us-east-1")
client_config={"boto_session": session}

# OK: region のみ（デフォルト認証チェーンを使用）
client_config={"region": "us-east-1"}
```

### 公開属性

```python
model.region          # "us-east-1"
model.model_id        # "amazon.nova-sonic-v1:0"
model.config          # dict: audio/inference/turn_detection を含む統合設定
model.config["audio"]["voice"]  # "tiffany"
# ※ model.client_config, model.provider_config は存在しない
```

## BidiAgent の入出力プロトコル

`BidiInput` / `BidiOutput` は Protocol（duck typing）で、`__call__`, `start(agent)`, `stop()` を実装する。

```python
from strands.experimental.bidi import BidiAgent
from strands.experimental.bidi.io import BidiAudioIO, BidiTextIO

# マイク/スピーカーで対話（CLI用）
audio_io = BidiAudioIO()
text_io = BidiTextIO()
await agent.run(inputs=[audio_io.input()], outputs=[audio_io.output(), text_io.output()])
```

## BidiAudioInputEvent

```python
from strands.experimental.bidi.events import BidiAudioInputEvent

BidiAudioInputEvent(
    audio=base64_encoded_string,  # base64 エンコードされた PCM 16bit LE データ
    format="pcm",
    sample_rate=16000,  # 必須（省略すると TypeError）
    channels=1          # 必須
)
```

## 受信イベント型

| イベント | 説明 |
|---------|------|
| `BidiConnectionStartEvent` | 接続確立 |
| `BidiUsageEvent` | トークン使用量 |
| `BidiResponseStartEvent` | レスポンス開始 |
| `BidiTranscriptStreamEvent` | テキストトランスクリプト（`role`, `text`, `is_final`） |
| `BidiAudioStreamEvent` | 音声出力データ（`audio`: base64） |
| `BidiResponseCompleteEvent` | レスポンス完了 |
| `BidiInterruptionEvent` | ユーザー割り込み検出（`reason`: `user_speech`） |
| `BidiConnectionCloseEvent` | 接続終了 |
| `BidiErrorEvent` | エラー |
| `ToolUseStreamEvent` | ツール呼び出し（`name`, `input`, `toolUseId`） |
| `ToolResultEvent` | ツール実行結果 |

**注意**: 出力イベントは TypedDict 形式（`event["type"]`, `event["audio"]` 等で dict アクセス）。`ToolUseStreamEvent` の type 文字列は `"tool_use_stream"`（`"bidi_"` プレフィックスなし）。

## ツール使用（Function Calling）

BidiAgent + Nova Sonic の音声対話中にツール呼び出しが正常に動作する。

```python
from strands import tool
from strands.experimental.bidi.tools import stop_conversation

@tool
def get_current_time() -> str:
    """現在の時刻を返します。"""
    from datetime import datetime, timezone, timedelta
    JST = timezone(timedelta(hours=9))
    now = datetime.now(JST)
    return now.strftime("%Y年%m月%d日 %H:%M JST")

agent = BidiAgent(
    model=model,
    tools=[stop_conversation, get_current_time],
    system_prompt="ツールを積極的に使ってください",
)
```

システムプロンプトで「ツールを積極的に使って」と指示すると呼び出し率が上がる。

## Nova Sonic の特性

- **Speech-to-Speech モデル**: テキスト入力だけでは応答しない（VAD が「発話→無音」を検出してターン切替）
- **日本語**: 公式対応言語に含まれないが、実際には日本語で動作する（ユーザー発話のトランスクリプトはローマ字）
- **レイテンシ**: 発話終了→最初の音声レスポンスまで約2.5秒（ツールなし）/ 約5秒（ツール使用時）
- **割り込み**: 応答中にユーザーが話すと `BidiInterruptionEvent` が発生し、音声出力が中断される

## AgentCore WebSocket サポート

`BedrockAgentCoreApp` は `@app.websocket` デコレータをネイティブサポート。BidiAgent との双方向ストリーミングブリッジに使用する。

```python
from bedrock_agentcore import BedrockAgentCoreApp

app = BedrockAgentCoreApp()

@app.websocket
async def websocket_handler(websocket, context):
    await websocket.accept()
    # websocket は Starlette の WebSocket インターフェース
    # receive_json(), send_json(), close() 等が使える
```

- デフォルトパス: `/ws`（ポート 8080）
- `@app.entrypoint`（HTTP SSE）とは別物
- ヘルスチェック `/ping` は AgentCore が自動処理

## カスタム BidiInput / BidiOutput（WebSocket ブリッジ）

ブラウザ ↔ WebSocket ↔ BidiAgent ↔ Nova Sonic のブリッジ実装パターン。

```python
class WebSocketBidiInput:
    def __init__(self, websocket): self.websocket = websocket
    async def start(self, agent): pass
    async def stop(self): pass
    async def __call__(self):
        while True:  # 非audioメッセージをスキップするループが必要
            data = await self.websocket.receive_json()
            if data.get("type") == "audio":
                return BidiAudioInputEvent(
                    audio=data["audio"], format="pcm",
                    sample_rate=16000, channels=1
                )

class WebSocketBidiOutput:
    def __init__(self, websocket): self.websocket = websocket
    async def start(self, agent): pass
    async def stop(self): pass
    async def __call__(self, event):
        event_type = event.get("type", "")
        if event_type == "bidi_audio_stream":
            await self.websocket.send_json({"type": "audio", "audio": event["audio"]})
        elif event_type == "bidi_transcript_stream":
            await self.websocket.send_json({
                "type": "transcript", "role": event["role"],
                "text": event["text"], "is_final": event["is_final"]
            })
```

**注意点**:
- 入力側の `__call__` は「次のチャンクが来るまでブロック」する設計
- WebSocket 切断時は `receive_json()` が例外を投げ、`run()` のループが終了する

## WebSocket メッセージプロトコル

**ブラウザ → バックエンド:**
```json
{"type": "audio", "audio": "<base64 PCM 16kHz 16bit mono>"}
```

**バックエンド → ブラウザ:**
```json
{"type": "audio", "audio": "<base64>"}
{"type": "transcript", "role": "user|assistant", "text": "...", "is_final": true}
{"type": "interruption"}
{"type": "tool_use", "name": "get_current_time"}
{"type": "error", "message": "..."}
```

## strands_tools（コミュニティツール）

BidiAgent にも通常の Agent にも使えるコミュニティ提供ツール。

```bash
pip install strands-agents-tools[rss]
```

```python
from strands_tools import rss

agent = BidiAgent(
    model=model,
    tools=[stop_conversation, rss],
    system_prompt="RSS フィード https://aws.amazon.com/about-aws/whats-new/recent/feed/ を使って最新情報を取得してください",
)
```

## Dockerfile（BidiAgent コンテナ）

`strands-agents[bidi]` は PyAudio を依存に含むため、C コンパイラと PortAudio が必要。

```dockerfile
FROM python:3.13-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    portaudio19-dev build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
EXPOSE 8080

CMD ["opentelemetry-instrument", "python", "agent.py"]
```

## テスト方法（マイクなし環境）

macOS の `say` + `ffmpeg` で音声ファイルを生成して送信：

```bash
say -v Kyoko -o /tmp/speech.aiff "こんにちは"
ffmpeg -y -i /tmp/speech.aiff -f s16le -acodec pcm_s16le -ar 16000 -ac 1 /tmp/speech.pcm
```

送信後は 2-3 秒の無音チャンクを追加して VAD のターン検出をトリガーする。

## 依存関係

```
strands-agents[bidi]    # BidiAgent + Nova Sonic
botocore[crt]           # AWS SSO認証（aws login）に必須
strands-agents-tools[rss]  # RSSフィードツール（オプション）
```

macOS では PyAudio のために `brew install portaudio` が必要。

---

## 参考リンク

- [Strands Agents - BidiAgent](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/bidirectional-streaming/agent/)
- [Strands Agents - Nova Sonic](https://strandsagents.com/latest/documentation/docs/user-guide/concepts/bidirectional-streaming/models/nova_sonic/)
- [Amazon Nova Sonic ユーザーガイド](https://docs.aws.amazon.com/nova/latest/userguide/speech.html)
- [AgentCore WebSocket Getting Started](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-get-started-websocket.html)