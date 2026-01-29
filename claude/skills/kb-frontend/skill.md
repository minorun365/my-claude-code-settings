---
name: kb-frontend
description: フロントエンド開発のナレッジ。React/Tailwind/Marp/SSE/Amplify UI等
user-invocable: true
---

# フロントエンド開発パターン

React/TypeScript/Tailwindを使ったフロントエンド開発の学びを記録する。

## Tailwind CSS v4

### Vite統合（ゼロコンフィグ）
```typescript
// vite.config.ts
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
```

### カスタムカラー定義
```css
/* src/index.css */
@import "tailwindcss";

@theme {
  --color-brand-blue: #0e0d6a;
}
```

### カスタムグラデーション
```css
.bg-brand-gradient {
  background: linear-gradient(to right, #1a3a6e, #5ba4d9);
}
```

## React ストリーミングUI

### イミュータブル更新（必須）
```typescript
// NG: シャローコピーしてオブジェクト直接変更 → StrictModeで2回実行され文字がダブる
setMessages(prev => {
  const newArr = [...prev];
  newArr[newArr.length - 1].content += chunk;
  return newArr;
});

// OK: map + スプレッド構文でイミュータブルに更新
setMessages(prev =>
  prev.map((msg, idx) =>
    idx === prev.length - 1 && msg.role === 'assistant'
      ? { ...msg, content: msg.content + chunk }
      : msg
  )
);
```

### タブ切り替え時の状態保持
```tsx
// NG: 条件レンダリングだとアンマウント時に状態が消える
{activeTab === 'chat' ? <Chat /> : <Preview />}

// OK: hiddenクラスで非表示にすれば状態が保持される
<div className={activeTab === 'chat' ? '' : 'hidden'}>
  <Chat />
</div>
<div className={activeTab === 'preview' ? '' : 'hidden'}>
  <Preview />
</div>
```

## Marp Core（ブラウザ用）

### 基本的な使い方
```typescript
import Marp from '@marp-team/marp-core';

const marp = new Marp();
const { html, css } = marp.render(markdown);

// SVG要素を抽出（DOM構造を維持）
const parser = new DOMParser();
const doc = parser.parseFromString(html, 'text/html');
const svgs = doc.querySelectorAll('svg[data-marpit-svg]');
```

### スライド表示
```tsx
<style>{css}</style>
<div className="marpit w-full h-full [&>svg]:w-full [&>svg]:h-full">
  <div dangerouslySetInnerHTML={{ __html: svg.outerHTML }} />
</div>
```

**重要**: `section`だけ抽出するとCSSセレクタがマッチしない。`div.marpit > svg > foreignObject > section` 構造が必要。

### iOS Safari対応（必須）

iOS Safari/Chromeでスライドが見切れる問題がある。これはWebKit Bug 23113（15年以上放置）が原因で、`<foreignObject>`内のHTMLがviewBox変換を正しく継承しない。

**解決策**: `marpit-svg-polyfill`を使用

```bash
npm install @marp-team/marpit-svg-polyfill
```

```tsx
import { useEffect, useRef } from 'react';
import { observe } from '@marp-team/marpit-svg-polyfill';

function SlidePreview({ markdown }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (containerRef.current) {
      const cleanup = observe(containerRef.current);
      return cleanup;
    }
  }, [markdown]);

  return (
    <div ref={containerRef}>
      {/* スライド表示 */}
    </div>
  );
}
```

**注意**: Chrome DevToolsのiOSエミュレーションでは再現しない（内部エンジンが異なるため）。実機テストが必須。

### Tailwind CSSとの競合

#### invertクラスの競合
Marpの`class: invert`とTailwindの`.invert`ユーティリティが競合する。

```css
/* src/index.css に追加 */
.marpit section.invert {
  filter: none !important;
}
```

#### 箇条書き（リストスタイル）の競合
Tailwind CSS v4のPreflight（CSSリセット）が`list-style: none`を適用するため、Marpスライド内の箇条書きビュレット（●○■）が消える。

```css
/* src/index.css に追加 */
.marpit ul {
  list-style: disc !important;
}

.marpit ol {
  list-style: decimal !important;
}

/* ネストされたリストのスタイル */
.marpit ul ul,
.marpit ol ul {
  list-style: circle !important;
}

.marpit ul ul ul,
.marpit ol ul ul {
  list-style: square !important;
}
```

### SVGのレスポンシブ対応（スマホ対応）

MarpのSVGは固定サイズ（1280x720px）の`width`/`height`属性を持っているため、スマホの狭い画面では見切れる。SVG属性を動的に変更して対応：

```typescript
const svgs = doc.querySelectorAll('svg[data-marpit-svg]');

return Array.from(svgs).map((svg, index) => {
  // SVGのwidth/height属性を100%に変更してレスポンシブ対応
  svg.setAttribute('width', '100%');
  svg.setAttribute('height', '100%');
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  return { index, html: svg.outerHTML };
});
```

**ポイント**:
- `width`/`height`を`100%`に → 親要素にフィット
- `preserveAspectRatio="xMidYMid meet"` → アスペクト比維持で中央配置
- CSSの`!important`よりSVG属性の直接変更が確実

**汎用パターン**: 外部ライブラリが生成する固定サイズSVGをレスポンシブにする場合に有効

## SSEストリーミング処理

### 基本パターン
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

### エラーハンドリング
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

### モック実装（ローカル開発用）

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

// 環境変数で切り替え
const useMock = import.meta.env.VITE_USE_MOCK === 'true';
const invoke = useMock ? invokeAgentMock : invokeAgent;
```

### PDF生成（Base64デコード・ダウンロード）

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

## Amplify UI React

### Authenticator（認証UI）
```tsx
import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';

function App() {
  return (
    <Authenticator>
      {({ signOut, user }) => (
        <main>
          <h1>Hello {user?.username}</h1>
          <button onClick={signOut}>Sign out</button>
        </main>
      )}
    </Authenticator>
  );
}
```

### 日本語化
```typescript
// main.tsx
import { I18n } from 'aws-amplify/utils';
import { translations } from '@aws-amplify/ui-react';

I18n.putVocabularies(translations);
I18n.setLanguage('ja');
```

### 認証画面のカスタマイズ（Header/Footer）

Cognito認証画面にアプリ名やプライバシーポリシーを表示する：

```tsx
const authComponents = {
  Header() {
    return (
      <div className="text-center py-4">
        <h1 className="text-2xl font-bold text-gray-800">アプリ名</h1>
        <p className="text-sm text-gray-500 mt-1">
          「Create Account」で誰でも利用できます！
        </p>
      </div>
    );
  },
  Footer() {
    return (
      <div className="text-center py-3 px-4">
        <p className="text-xs text-gray-400 leading-relaxed">
          登録されたメールアドレスは認証目的でのみ使用します。
        </p>
      </div>
    );
  },
};

<Authenticator components={authComponents}>
  {({ signOut }) => <MainApp signOut={signOut} />}
</Authenticator>
```

**用途例**:
- Header: アプリ名、利用ガイド、ロゴ
- Footer: プライバシーポリシー、免責事項、メールアドレスの利用目的

### 認証画面の配色カスタマイズ（CSS方式）

`createTheme`/`ThemeProvider`ではグラデーションが使えないため、CSSで直接スタイリングするのが確実。

```css
/* src/index.css */

/* プライマリボタン（グラデーション対応） */
[data-amplify-authenticator] .amplify-button--primary {
  background: linear-gradient(to right, #1a3a6e, #5ba4d9);
  border: none;
}

[data-amplify-authenticator] .amplify-button--primary:hover {
  background: linear-gradient(to right, #142d54, #4a93c8);
}

/* リンク（パスワードを忘れた等） */
[data-amplify-authenticator] .amplify-button--link {
  color: #1a3a6e;
}

/* タブ */
[data-amplify-authenticator] .amplify-tabs__item--active {
  color: #1a3a6e;
  border-color: #5ba4d9;
}

/* 入力フォーカス */
[data-amplify-authenticator] input:focus {
  border-color: #5ba4d9;
  box-shadow: 0 0 0 2px rgba(91, 164, 217, 0.2);
}
```

**ポイント**:
- `[data-amplify-authenticator]`セレクタで認証画面のみに適用
- `createTheme`はグラデーション非対応 → CSS直接指定が確実
- アプリ本体と同じ配色を使用して統一感を出す

## ステータス表示パターン

### 重複防止（ツール使用イベント）

LLMのストリーミングでは、同じツールに対して複数の`tool_use`イベントが送信されることがある。
ステータスメッセージの重複を防ぐには、追加前に既存チェックが必要。

```typescript
onToolUse: (toolName) => {
  if (toolName === 'output_slide') {
    setMessages(prev => {
      // 既存のステータスがあればスキップ
      const hasExisting = prev.some(
        msg => msg.isStatus && msg.statusText === 'スライドを生成中...'
      );
      if (hasExisting) return prev;
      return [
        ...prev,
        { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
      ];
    });
  }
},
```

### 複数ステータスのアイコン切り替え

完了状態のステータスが複数ある場合、OR条件でチェックマークを表示。

```tsx
// NG: 1つの完了状態のみ
{message.statusText === '生成しました' ? <CheckIcon /> : <Spinner />}

// OK: 複数の完了状態に対応
{message.statusText === '生成しました' || message.statusText === '検索完了' ? (
  <span className="text-green-600">✓</span>
) : (
  <span className="animate-spin">◌</span>
)}
```

### ステータス遷移の連動

前のステータスを完了に更新しつつ、新しいステータスを追加する場合。

```typescript
// Web検索 → スライド生成 の遷移例
if (toolName === 'output_slide') {
  setMessages(prev => {
    // Web検索中を完了に更新
    const updated = prev.map(msg =>
      msg.isStatus && msg.statusText === 'Web検索中...'
        ? { ...msg, statusText: 'Web検索完了' }
        : msg
    );
    // 新しいステータスを追加
    return [
      ...updated,
      { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
    ];
  });
}
```

### SSEストリーミング時の複数ツール発火対応

同一ツールの`onToolUse`が複数回発火する場合、**重複チェック + テキスト受信時の自動完了** の組み合わせで対処する。

```typescript
onToolUse: (toolName) => {
  if (toolName === 'web_search') {
    setMessages(prev => {
      // 進行中のステータスがあればスキップ（同一呼び出しの重複防止）
      const hasInProgress = prev.some(
        msg => msg.isStatus && msg.statusText === 'Web検索中...'
      );
      if (hasInProgress) return prev;
      return [
        ...prev,
        { role: 'assistant', content: '', isStatus: true, statusText: 'Web検索中...' }
      ];
    });
  }
},
onText: (text) => {
  setMessages(prev => {
    // テキスト受信時に進行中のステータスを自動完了
    let msgs = prev.map(msg =>
      msg.isStatus && msg.statusText === 'Web検索中...'
        ? { ...msg, statusText: 'Web検索完了' }
        : msg
    );
    // 以降の処理はmsgsを使う（prevではなく）
    return [...msgs, { role: 'assistant', content: text }];
  });
}
```

**ポイント**: `prev`をmapした結果は新しい配列。後続処理ではmap結果の変数（`msgs`）を使うこと。`prev`を参照すると変更が反映されない。

## 環境変数の読み込み（.env vs .env.local）

| フレームワーク/ツール | .env | .env.local | 備考 |
|-----------|------|-----------|------|
| Vite | ○ | ○ | 両方読む（優先度: .env.local > .env） |
| Next.js | ○ | ○ | 両方読む |
| **Node.js dotenv** | ○ | × | `.env` のみ |

Amplify CDK（`import 'dotenv/config'`）とViteの両方で使う場合は **`.env`** に統一する。

## Marp Coreカスタムテーマ

### テーマの追加方法

```typescript
import Marp from '@marp-team/marp-core';
import customTheme from '../themes/custom.css?raw';  // Viteの?rawでCSSを文字列として読み込み

const marp = new Marp();
marp.themeSet.add(customTheme);  // カスタムテーマを登録
const { html, css } = marp.render(markdown);
```

### コミュニティテーマの利用

Marpコミュニティテーマ（例: border）を使う場合:
1. CSSファイルをダウンロード
2. `src/themes/` に配置
3. `?raw` サフィックスでインポート
4. `marp.themeSet.add()` で登録

**参考**: https://rnd195.github.io/marp-community-themes/

### フロントエンドとバックエンドの両方に配置

カスタムテーマを使う場合、以下の両方に配置が必要:
- `src/themes/xxx.css` - フロントエンド（Marp Core）用
- `amplify/agent/runtime/xxx.css` - バックエンド（Marp CLI PDF生成）用

PDF生成時は `--theme` オプションでCSSファイルを指定:
```python
cmd = ["marp", md_path, "--pdf", "--theme", str(theme_path)]
```

## OGP/Twitterカード設定

### 推奨設定（summaryカード）

Twitterで画像付きカードを表示するための完全な設定。`og:*` と `twitter:*` の両方を明示的に指定することが重要。

```html
<!-- OGP -->
<meta property="og:title" content="タイトル" />
<meta property="og:description" content="説明" />
<meta property="og:type" content="website" />
<meta property="og:url" content="https://example.com/" />
<meta property="og:image" content="https://example.com/ogp.jpg?v=2" />
<meta property="og:image:secure_url" content="https://example.com/ogp.jpg?v=2" />
<meta property="og:image:width" content="512" />
<meta property="og:image:height" content="512" />
<meta property="og:image:type" content="image/jpeg" />

<!-- Twitter Card -->
<meta name="twitter:card" content="summary" />
<meta name="twitter:site" content="@username" />
<meta name="twitter:title" content="タイトル" />
<meta name="twitter:description" content="説明" />
<meta name="twitter:image" content="https://example.com/ogp.jpg?v=2" />
```

### カード種類と画像サイズ

| カード種類 | 表示 | 推奨画像サイズ |
|-----------|------|---------------|
| `summary` | 小さい画像が右側 | 512x512（正方形） |
| `summary_large_image` | 大きい画像が上部 | 1200x630（横長） |

### 画像のExif削除

iPhoneで撮った画像などはExifメタデータが含まれている場合がある。削除推奨。

```python
from PIL import Image
img = Image.open('original.jpg')
img_clean = Image.new('RGB', img.size)
img_clean.paste(img)
img_clean.save('ogp.jpg', 'JPEG', quality=85)
```

### キャッシュ対策

画像URLにバージョンパラメータを追加してキャッシュを回避：
- `ogp.jpg?v=2` のようにクエリパラメータを追加
- 変更後は [Twitter Card Validator](https://cards-dev.twitter.com/validator) で再検証
