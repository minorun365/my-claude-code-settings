---
name: kb-frontend-sse
description: SSEストリーミング処理のナレッジ。基本パターン/タイムアウト/リトライ/モック/PDF生成等
user-invocable: true
---

# SSEストリーミング処理

SSE（Server-Sent Events）を使ったフロントエンドのストリーミング処理パターンを記録する。

## 基本パターン

```typescript
const reader = response.body?.getReader();
const decoder = new TextDecoder();
let buffer = '';

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  buffer += decoder.decode(value, { stream: true });
  const lines = buffer.split('\n');
  buffer = lines.pop() || '';  // 不完全な行は次回に持ち越し

  for (const line of lines) {
    if (line.startsWith('data: ')) {
      const data = line.slice(6);
      if (data === '[DONE]') return;
      try {
        const event = JSON.parse(data);
        handleEvent(event);
      } catch {
        // JSONパースエラーは無視
      }
    }
  }
}
```

## イベントハンドリング

```typescript
function handleEvent(event) {
  // APIによってcontent/dataのどちらかにペイロードが入る
  const textValue = event.content || event.data;

  switch (event.type) {
    case 'text':
      onText(textValue);
      break;
    case 'tool_use':
      onToolUse(textValue);  // ツール名が返る
      break;
    case 'markdown':
      onMarkdown(textValue);
      break;
    case 'error':
      onError(new Error(event.error || event.message || textValue));
      break;
  }
}
```

## エラーハンドリング

```typescript
// ストリーミング中のエラー
case 'error':
  if (event.error || event.message) {
    callbacks.onError(new Error(event.error || event.message));
  }
  break;

// HTTPエラー
const response = await fetch(url, options);
if (!response.ok) {
  throw new Error(`API Error: ${response.status} ${response.statusText}`);
}
```

## アイドルタイムアウト（2段構成）

SSEストリームに2段階のタイムアウトを設定し、接続障害と推論ハングの両方を検知するパターン：

```typescript
async function readSSEStream(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onEvent: (event: Record<string, unknown>) => void,
  idleTimeoutMs?: number,          // 初回イベント受信前（短め: 10秒）
  ongoingIdleTimeoutMs?: number    // イベント間（長め: 60秒）
): Promise<void> {
  let firstEventReceived = false;

  while (true) {
    // フェーズに応じてタイムアウト値を切り替え
    const currentTimeout = firstEventReceived ? ongoingIdleTimeoutMs : idleTimeoutMs;
    if (currentTimeout) {
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new SSEIdleTimeoutError(currentTimeout)), currentTimeout);
      });
      readResult = await Promise.race([reader.read(), timeoutPromise]);
    } else {
      readResult = await reader.read();
    }
    // ... イベント処理後に firstEventReceived = true
  }
}
```

| フェーズ | タイムアウト | 検知対象 |
|---------|------------|---------|
| 初回イベント受信前 | 短め（10秒） | スロットリング、接続エラー |
| イベント間（初回受信後） | 長め（60秒） | 推論ハング、モデル無応答 |

**設計ポイント**:
- 初回タイムアウトは短く → ユーザーを素早くエラーに気づかせる
- イベント間タイムアウトは長めに → 正常な推論やツール実行を妨げない

## モック実装（ローカル開発用）

```typescript
export async function invokeAgentMock(prompt, callbacks) {
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  const thinkingText = `${prompt}について考えています...`;
  for (const char of thinkingText) {
    callbacks.onText(char);
    await sleep(20);
  }

  callbacks.onStatus('生成中...');
  await sleep(1000);

  callbacks.onMarkdown('# 生成結果\n\n...');
  callbacks.onComplete();
}

// 環境変数で切り替え
const useMock = import.meta.env.VITE_USE_MOCK === 'true';
const invoke = useMock ? invokeAgentMock : invokeAgent;
```

## エクスポートのリトライパターン（ネットワーク耐性）

SSE経由のファイルエクスポート（PDF/PPTX等）は、不安定なネットワークでストリームが切断されることがある：

```typescript
export async function exportSlide(
  markdown: string,
  format: ExportFormat,
  theme: string = 'border'
): Promise<Blob> {
  const MAX_RETRIES = 1;
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    try {
      return await _exportSlideOnce(markdown, format, theme);
    } catch (e) {
      lastError = e as Error;
      if (attempt < MAX_RETRIES) {
        console.warn(`Export failed (attempt ${attempt + 1}), retrying...`, e);
        await new Promise(r => setTimeout(r, 1000));
      }
    }
  }
  throw lastError!;
}
```

**ポイント**:
- SSE `reader.read()` が `done: true` を返しても `resultBlob` が null = ストリーム切断
- リトライは1回（計2回）で十分
- バックエンド側のkeep-alive（5秒ごとの progress イベント）と組み合わせるとさらに効果的

## PDF生成（Base64デコード・ダウンロード）

```typescript
export async function exportPdf(markdown: string): Promise<Blob> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { /* 認証ヘッダー等 */ },
    body: JSON.stringify({ action: 'export_pdf', markdown }),
  });

  const reader = response.body?.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const event = JSON.parse(line.slice(6));
        if (event.type === 'pdf' && event.data) {
          const binaryString = atob(event.data);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          return new Blob([bytes], { type: 'application/pdf' });
        }
      }
    }
  }
  throw new Error('PDF生成に失敗しました');
}

// ダウンロード処理
const blob = await exportPdf(markdown);
const url = URL.createObjectURL(blob);
const a = document.createElement('a');
a.href = url;
a.download = 'slide.pdf';
a.click();
URL.revokeObjectURL(url);
```
