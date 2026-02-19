---
name: kb-web-audio
description: Web Audio API / WebSocket / 音声対話UIのナレッジ。PCM再生、マイク入力、SigV4認証、トランスクリプト表示
user-invocable: true
---

# Web Audio / WebSocket / 音声対話UI

ブラウザでの音声処理・WebSocket接続・音声対話UIの学びを記録する。
一般的なフロントエンド開発パターンは `/kb-frontend` を参照。バックエンドの BidiAgent 実装は `/kb-bidi-agent` を参照。

## Web Audio API

### 音声再生: AudioBufferSourceNode スケジューリング方式（推奨）

低サンプルレート（16kHz）の PCM 音声チャンクをブラウザで安定再生する方式。AudioWorklet リングバッファ方式は macOS で不安定なため、こちらを推奨。

```typescript
// AudioContext はネイティブサンプルレートで作成（16kHz を強制しない）
const ctx = new AudioContext();
await ctx.resume(); // 自動再生ポリシー対策（必須！）

const nextPlayTimeRef = useRef(0);
const activeSourcesRef = useRef<AudioBufferSourceNode[]>([]);

function playChunk(int16Data: Int16Array) {
  const audioBuffer = ctx.createBuffer(1, int16Data.length, 16000);
  const channelData = audioBuffer.getChannelData(0);
  for (let i = 0; i < int16Data.length; i++) {
    channelData[i] = int16Data[i] / 32768; // Int16 → Float32
  }

  const source = ctx.createBufferSource();
  source.buffer = audioBuffer;
  source.connect(ctx.destination);

  const startTime = Math.max(nextPlayTimeRef.current, ctx.currentTime);
  source.start(startTime);
  nextPlayTimeRef.current = startTime + audioBuffer.duration;
  activeSourcesRef.current.push(source);

  source.onended = () => {
    activeSourcesRef.current = activeSourcesRef.current.filter(s => s !== source);
  };
}

// 割り込み時: 全ソースを停止してバッファクリア
function stopAllPlayback() {
  activeSourcesRef.current.forEach(s => { try { s.stop(); } catch {} });
  activeSourcesRef.current = [];
  nextPlayTimeRef.current = 0;
}
```

**AudioWorklet リングバッファを使わない理由**:
- `AudioContext({ sampleRate: 16000 })` は macOS で不安定（ハードウェアは通常 48kHz）
- リングバッファはネットワークジッターに弱い（バッファ枯渇→無音→溜まると早送り再生）
- AudioBufferSourceNode 方式なら Web Audio API が自動でリサンプリング（16kHz→ネイティブ）

**重要**: `AudioContext.resume()` をユーザーインタラクション時に呼ばないと、ブラウザの自動再生ポリシーで音が出ない。

### マイク入力: AudioWorklet（PCM キャプチャ）

```javascript
// pcm-capture-processor.js（AudioWorklet）
class PcmCaptureProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0][0]; // mono channel
    if (!input) return true;

    // Float32 → Int16 変換
    const int16 = new Int16Array(input.length);
    for (let i = 0; i < input.length; i++) {
      const s = Math.max(-1, Math.min(1, input[i]));
      int16[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
    }

    this.port.postMessage(int16.buffer, [int16.buffer]); // Transferable で効率的
    return true;
  }
}
registerProcessor('pcm-capture-processor', PcmCaptureProcessor);
```

```typescript
// メインスレッド側
const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
const audioCtx = new AudioContext({ sampleRate: 16000 });
await audioCtx.audioWorklet.addModule('/pcm-capture-processor.js');

const source = audioCtx.createMediaStreamSource(stream);
const workletNode = new AudioWorkletNode(audioCtx, 'pcm-capture-processor');

workletNode.port.onmessage = (event) => {
  const int16Buffer = new Int16Array(event.data);
  const base64 = int16ToBase64(int16Buffer);
  websocket.send(JSON.stringify({ type: 'audio', audio: base64 }));
};

source.connect(workletNode);
```

### base64 変換ユーティリティ

```typescript
// base64 → Int16Array（受信した音声データのデコード）
function base64ToInt16(base64: string): Int16Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return new Int16Array(bytes.buffer);
}

// Int16Array → base64（マイク入力データのエンコード）
function int16ToBase64(int16: Int16Array): string {
  const bytes = new Uint8Array(int16.buffer);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}
```

---

## WebSocket（SigV4 Presigned URL 認証）

ブラウザの WebSocket API はカスタムヘッダー（`Authorization`）を設定できないため、**SigV4 事前署名 URL** を使う。

```typescript
import { SignatureV4 } from '@smithy/signature-v4';
import { HttpRequest } from '@smithy/protocol-http';
import { Sha256 } from '@aws-crypto/sha256-js';
import { fetchAuthSession } from 'aws-amplify/auth';

async function createPresignedWebSocketUrl(hostname: string, path: string, region: string) {
  const session = await fetchAuthSession();
  const credentials = session.credentials; // Cognito Identity Pool の IAM 認証情報

  const signer = new SignatureV4({
    service: 'bedrock-agentcore', region,
    credentials, sha256: Sha256,
  });

  const request = new HttpRequest({
    method: 'GET', protocol: 'https:', hostname, path,
    query: { qualifier: 'DEFAULT' },
    headers: { host: hostname },
  });

  const presigned = await signer.presign(request, { expiresIn: 300 });
  // presigned.query から RFC 3986 形式でクエリ文字列を構築
  const queryString = Object.entries(presigned.query!)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v as string)}`)
    .join('&');

  return `wss://${hostname}${path}?${queryString}`;
}
```

**ポイント**:
- `service` は `bedrock-agentcore`（Bedrock AgentCore の WebSocket エンドポイント用）
- ARN はエンコードしない（公式サンプル準拠）
- `qualifier=DEFAULT` は必須
- `Amplify.getConfig()` は `custom` フィールドを返さない → `amplify_outputs.json` を直接 import

---

## トランスクリプト表示パターン（音声対話UI）

### アシスタントの非final は字幕方式で

音声対話（Nova Sonic 等）のトランスクリプトは**音声再生より先にテキストが届く**。アシスタントの非final テキストをそのまま表示すると「未来の内容で上書き」される問題がある。

```typescript
function handleTranscript(role: string, text: string, isFinal: boolean) {
  // アシスタント非final → インジケーターのみ（テキストは表示しない）
  if (role === 'assistant' && !isFinal) {
    setIsAssistantSpeaking(true);
    return;
  }

  // final → インジケーター消去 + 履歴に追加
  if (role === 'assistant') setIsAssistantSpeaking(false);

  // ユーザー側の非final はリアルタイム表示OK（自分の発話なので先行しても問題ない）
  setTranscripts(prev => {
    const last = prev[prev.length - 1];
    if (last && last.role === role && !last.isFinal) {
      // 同一ロールの非final を上書き
      return [...prev.slice(0, -1), { role, text, isFinal }];
    }
    return [...prev, { role, text, isFinal }];
  });
}
```

**ポイント**:
- アシスタントの非final は「話し中インジケーター（・・・バウンスドット）」で表示
- `isFinal` の値に関わらず、直前エントリが同じロールで非final なら上書き（重複防止）