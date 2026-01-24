# LLMアプリ開発パターン

プロジェクト横断で得たLLMアプリ開発の学びを記録する。

## Strands Agents

### Agent作成
```python
from strands import Agent

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="あなたはアシスタントです",
)
```

### 同期実行
```python
result = agent(prompt)
print(result)
```

### ストリーミング実行
```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

## プロンプト設計

### スライド生成の例
```markdown
あなたは「パワポ作るマン」、プロフェッショナルなスライド作成AIアシスタントです。

## 役割
ユーザーの指示に基づいて、Marp形式のマークダウンでスライドを作成・編集します。

## スライド作成ルール
- フロントマターには `marp: true` を含める
- スライド区切りは `---` を使用
- 1枚目はタイトルスライド（タイトル + サブタイトル）
- 箇条書きは1スライドあたり3〜5項目に抑える
- 適度に絵文字を使って視覚的に分かりやすく

## 出力形式
スライドを生成・編集したら、マークダウン全文を ```markdown コードブロックで出力してください。
```

## ストリーミング実装

### フロントエンド（SSE処理）
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

### イベントハンドリング
```typescript
function handleEvent(event) {
  // APIによってcontent/dataのどちらかにペイロードが入る
  const textValue = event.content || event.data;

  switch (event.type) {
    case 'text':
      onText(textValue);
      break;
    case 'error':
      onError(new Error(event.error || event.message || textValue));
      break;
    // ...
  }
}
```

## エラーハンドリング

### ストリーミング中のエラー
APIがエラーを返す場合、SSEイベントとして `{"type": "error", "error": "..."}` 形式で返ることがある。
UIに適切に表示するため、`error` タイプのハンドリングを実装する。

```typescript
case 'error':
  if (event.error || event.message) {
    callbacks.onError(new Error(event.error || event.message));
  }
  break;
```

### HTTPエラー
```typescript
const response = await fetch(url, options);

if (!response.ok) {
  throw new Error(`API Error: ${response.status} ${response.statusText}`);
}
```

## モック実装（ローカル開発用）

```typescript
export async function invokeAgentMock(prompt, callbacks) {
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // 思考過程をストリーミング
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
```

環境変数で切り替え：
```typescript
const useMock = import.meta.env.VITE_USE_MOCK === 'true';
const invoke = useMock ? invokeAgentMock : invokeAgent;
```
