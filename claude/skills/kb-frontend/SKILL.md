---
name: kb-frontend
description: フロントエンド開発のナレッジ。React/Tailwind/ステータス管理/モバイルUI等
user-invocable: true
---

# フロントエンド開発パターン

React/TypeScript/Tailwindを使ったフロントエンド開発の学びを記録する。

SSEストリーミング処理は `/kb-frontend-sse`、Amplify UI は `/kb-frontend-amplify-ui` を参照。

## Tailwind CSS v4

### 2つの統合方式

Tailwind CSS v4 には2つの統合方式がある。通常は Vite プラグイン方式（推奨）を使うが、dev サーバーで動作しない場合は PostCSS 方式にフォールバックする。

| 方式 | パッケージ | 仕組み | 推奨度 |
|------|-----------|--------|--------|
| Vite プラグイン | `@tailwindcss/vite` | Vite の `transform` フックで CSS を処理 | 公式推奨 |
| PostCSS | `@tailwindcss/postcss` | Vite 組み込みの CSS パイプライン経由 | フォールバック |

### Vite プラグイン方式（推奨）
```typescript
// vite.config.ts
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
```

### PostCSS 方式（フォールバック）
```javascript
// postcss.config.js
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```
```typescript
// vite.config.ts - tailwindcss プラグインは不要
export default defineConfig({
  plugins: [react()],
})
```

### 動作確認方法

ブラウザで CSS を確認し、先頭に `/*! tailwindcss v4.x.x | MIT License */` が表示されていれば正常。

### カスタムカラー定義
```css
/* src/index.css */
@import "tailwindcss";

@theme {
  --color-brand-blue: #0e0d6a;
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

### フェードインアニメーションの発火（keyを変える）

```tsx
<div
  key={isSearching ? `search-${statusText}` : index}
  className={`status-box ${isSearching ? 'animate-fade-in' : ''}`}
>
  {statusText}
</div>
```

## モバイルUI対応（iOS Safari）

### ドロップダウンメニューはhoverではなくクリック/タップベースで実装

iOS Safariでは`:hover`がタップで正しく動作しない。

```tsx
// NG: CSS hoverベース（iOSで動作しない）
<div className="relative group">
  <button>メニュー ▼</button>
  <div className="opacity-0 invisible group-hover:opacity-100 group-hover:visible">...</div>
</div>

// OK: useState + onClick ベース
function Dropdown() {
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent | TouchEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      document.addEventListener('touchstart', handleClickOutside);  // iOS対応
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('touchstart', handleClickOutside);
    };
  }, [isOpen]);

  return (
    <div className="relative" ref={dropdownRef}>
      <button onClick={() => setIsOpen(!isOpen)}>メニュー ▼</button>
      {isOpen && (
        <div className="absolute right-0 top-full mt-1 bg-white border rounded-lg shadow-lg z-10">
          <button onClick={() => { setIsOpen(false); handleOption1(); }}
            className="block w-full px-4 py-2 hover:bg-gray-100 active:bg-gray-200">
            オプション1
          </button>
        </div>
      )}
    </div>
  );
}
```

## ステータス表示パターン

### 重複防止（ツール使用イベント）

```typescript
onToolUse: (toolName) => {
  if (toolName === 'output_slide') {
    setMessages(prev => {
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

### ステータス遷移の連動

前のステータスを完了に更新しつつ、新しいステータスを追加する：

```typescript
if (toolName === 'output_slide') {
  setMessages(prev => {
    const updated = prev.map(msg =>
      msg.isStatus && msg.statusText === 'Web検索中...'
        ? { ...msg, statusText: 'Web検索完了' }
        : msg
    );
    return [
      ...updated,
      { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
    ];
  });
}
```

### SSEストリーミング時の複数ツール発火対応

```typescript
onText: (text) => {
  stopTipRotation();
  setMessages(prev => {
    // テキスト受信時に全ての進行中ステータスを自動完了
    let msgs = prev.map(msg => {
      if (msg.isStatus && msg.statusText?.startsWith('Web検索中'))
        return { ...msg, statusText: 'Web検索完了' };
      if (msg.isStatus && msg.statusText?.startsWith('スライドを生成中'))
        return { ...msg, statusText: 'スライドを生成しました', tipIndex: undefined };
      return msg;
    });
    return [...msgs, { role: 'assistant', content: text }];
  });
}
```

**重要**: テキスト受信（`onText`）はツール完了のシグナルとして機能する。`prev`をmapした結果は新しい配列。後続処理ではmap結果の変数（`msgs`）を使うこと。

## 疑似ストリーミング表示（1文字ずつ表示）

```typescript
const streamMessage = async (message: string) => {
  setMessages(prev => [...prev, { role: 'assistant', content: '', isStreaming: true }]);

  for (const char of message) {
    await new Promise(resolve => setTimeout(resolve, 30));
    setMessages(prev =>
      prev.map((msg, idx) =>
        idx === prev.length - 1 && msg.isStreaming
          ? { ...msg, content: msg.content + char }
          : msg
      )
    );
  }

  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.isStreaming
        ? { ...msg, isStreaming: false }
        : msg
    )
  );
};
```

### finallyブロックとの競合に注意

コールバック内で疑似ストリーミングを呼ぶ場合、毎回 `isStreaming: true` を設定してカーソル表示を維持する：

```typescript
// ✅ 毎回 isStreaming: true を設定
for (const char of message) {
  await new Promise(resolve => setTimeout(resolve, 30));
  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.role === 'assistant'
        ? { ...msg, content: msg.content + char, isStreaming: true }
        : msg
    )
  );
}
```

## 非同期コールバック内でのエラーハンドリング

`onError`コールバック内で`throw error`しても外側の`try-catch`には伝播しない。コールバック内で直接状態を更新する：

```typescript
// ❌ NG: throw しても外側の catch に届かない
onError: (error) => { throw error; },

// ✅ OK: コールバック内で直接状態を更新
onError: (error) => {
  const errorMessage = error instanceof Error ? error.message : String(error);
  const isModelNotAvailable = errorMessage.includes('model identifier is invalid');
  const displayMessage = isModelNotAvailable
    ? 'モデルがまだ利用できません。リリースをお待ちください！'
    : 'エラーが発生しました。もう一度お試しください。';
  streamErrorMessage(displayMessage);
  setIsLoading(false);
},
```

## 環境変数の読み込み（.env vs .env.local）

| フレームワーク/ツール | .env | .env.local | 備考 |
|-----------|------|-----------|------|
| Vite | ○ | ○ | 両方読む（優先度: .env.local > .env） |
| Next.js | ○ | ○ | 両方読む |
| **Node.js dotenv** | ○ | × | `.env` のみ |

Amplify CDK（`import 'dotenv/config'`）とViteの両方で使う場合は **`.env`** に統一する。

## OGP/Twitterカード設定

### 推奨設定（summaryカード）

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

| カード種類 | 表示 | 推奨画像サイズ |
|-----------|------|---------------|
| `summary` | 小さい画像が右側 | 512x512（正方形） |
| `summary_large_image` | 大きい画像が上部 | 1200x630（横長） |

### 画像のExif削除

```python
from PIL import Image
img = Image.open('original.jpg')
img_clean = Image.new('RGB', img.size)
img_clean.paste(img)
img_clean.save('ogp.jpg', 'JPEG', quality=85)
```

## Tailwind CSS Tips

### リストの行頭記号（箇条書き）

Tailwind CSS v4のPreflightが`list-style: none`を適用するため、デフォルトで箇条書きの記号が表示されない。

```tsx
// NG: 行頭記号が表示されない
<ul className="text-sm">

// OK: list-disc list-inside を追加
<ul className="text-sm list-disc list-inside">
```

### CSSショートハンドの !important 落とし穴

```css
/* NG */
.marpit ul { list-style: disc !important; }
/* OK */
.marpit ul { list-style-type: disc !important; }
```

## モーダルの状態管理パターン

### 確認 → 処理中 → 結果表示の3段階モーダル

```tsx
const [showConfirm, setShowConfirm] = useState(false);
const [isProcessing, setIsProcessing] = useState(false);
const [result, setResult] = useState<Result | null>(null);

const handleConfirm = async () => {
  setIsProcessing(true);
  try {
    const result = await doSomething();
    setShowConfirm(false);  // 処理完了後に閉じる
    setResult(result);
  } catch (error) {
    setShowConfirm(false);
    alert(`エラー: ${error.message}`);
  } finally {
    setIsProcessing(false);
  }
};
```

**ポイント**: モーダルを閉じるのは処理完了後。閉じるのが先だと「処理中...」が見えない。
