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

### LLMに特定のフォーマットを強制するテクニック

LLMに特定のクラスやフォーマットを確実に使わせるには、以下のテクニックが有効：

1. **「必須」「推奨」の強い表現を使う**
   - 「〜してください」より「**必ず**〜してください」
   - 「〜を使用」より「**必須**：〜を使用」

2. **テンプレート構成を具体的に示す**
   ```
   ## スライド構成のテンプレート（この構成に従ってください）
   1. タイトル（**必ず top クラス**）
   2. 導入（通常スライド）
   3. セクション区切り（**crosshead クラス推奨**）
   ...
   ```

3. **クラスの効果・メリットを説明する**
   - 「背景色が変わり、視覚的にメリハリがつきます」
   - 「プロフェッショナルなスライドになります」

4. **具体的なコード例を複数提示する**
   ```
   ### タイトルスライド【必須】
   最初のスライドには**必ず** `top` クラスを使用してください。
   ```markdown
   <!-- _class: top -->
   # タイトル
   ```
   ```

**ポイント**: 単に「使ってください」ではなく、「必須」「推奨」の区別を明確にし、使う理由（効果）も説明すると従いやすい。

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

## ツール駆動型の出力パターン

LLMが生成したコンテンツ（マークダウン等）をテキストストリームに直接出力すると、フロントエンドでの除去処理が複雑になる。出力専用のツールを作成し、ツール経由で出力させる方式が有効。

### バックエンド（Python）
```python
@tool
def output_content(content: str) -> str:
    """生成したコンテンツを出力します。"""
    global _generated_content
    _generated_content = content
    return "出力完了"
```

### フロントエンド（ステータス表示）
```typescript
onToolUse: (toolName) => {
  if (toolName === 'output_content') {
    setMessages(prev => [
      ...prev,
      { role: 'assistant', isStatus: true, statusText: 'コンテンツを生成中...' }
    ]);
  }
},
onMarkdown: (content) => {
  // ステータスを完了に更新
  setMessages(prev =>
    prev.map(msg =>
      msg.isStatus ? { ...msg, statusText: '生成完了' } : msg
    )
  );
}
```

**メリット**:
- テキストストリームにコンテンツが混入しない
- ツール使用中のステータス表示が容易
- フロントエンドのフィルタリング処理が不要

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

## PDF生成（AgentCore経由）

### バックエンド（Python）
```python
import base64
import subprocess
import tempfile
from pathlib import Path

def generate_pdf(markdown: str) -> bytes:
    """Marp CLIでPDFを生成"""
    with tempfile.TemporaryDirectory() as tmpdir:
        md_path = Path(tmpdir) / "slide.md"
        pdf_path = Path(tmpdir) / "slide.pdf"

        md_path.write_text(markdown, encoding="utf-8")

        result = subprocess.run(
            ["marp", str(md_path), "--pdf", "-o", str(pdf_path)],
            capture_output=True,
            text=True,
        )

        if result.returncode != 0:
            raise RuntimeError(f"Marp CLI error: {result.stderr}")

        return pdf_path.read_bytes()

@app.entrypoint
async def invoke(payload):
    if payload.get("action") == "export_pdf":
        markdown = payload.get("markdown", "")
        pdf_bytes = generate_pdf(markdown)
        pdf_base64 = base64.b64encode(pdf_bytes).decode("utf-8")
        yield {"type": "pdf", "data": pdf_base64}
        return
    # 通常のチャット処理...
```

### フロントエンド（Base64デコード・ダウンロード）
```typescript
export async function exportPdf(markdown: string): Promise<Blob> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { /* 認証ヘッダー等 */ },
    body: JSON.stringify({ action: 'export_pdf', markdown }),
  });

  // SSEレスポンスからPDFイベントを取得
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
          // Base64デコードしてBlobを返す
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
