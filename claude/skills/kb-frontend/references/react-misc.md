# React周辺の小ネタとトラブルシューティング

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

## トラブルシューティング

### Tailwind CSS v4: dev サーバーでユーティリティクラスが生成されない

**症状**: `npx vite` の dev サーバーで Tailwind のユーティリティクラスが一切生成されない。ビルドでは正常

**原因**: `@tailwindcss/vite` プラグインの `transform` ハンドラーが Vite 7 の dev サーバーモードで呼ばれない場合がある

**解決策**: `@tailwindcss/postcss`（PostCSS 方式）に切り替える（設定例は上記「Tailwind CSS v4」セクション参照）

### SSE: チャットの吹き出しが空のまま

**症状**: APIは成功（200）だが、UIに内容が表示されない

**原因**: APIは`event.data`を返すが、コードは`event.content`を期待していた

**解決策**: 両方に対応 → `const textValue = event.content || event.data;`

### 疑似ストリーミング: エラーメッセージが表示されない

**症状**: `onError`コールバックで疑似ストリーミングを開始しても、メッセージが表示されない

**原因**: `finally`ブロックが先に実行され`isStreaming: false`になるため、ストリーミングループ内のチェックが失敗

**解決策**: ループ内で`isStreaming`チェックを削除し、`idx === prev.length - 1 && msg.role === 'assistant'` のみで判定

### Twitter/Xシェア: ツイートボックスにテキストが入力されない

**症状**: シェアリンクをクリックしてTwitterを開いても、テキストが空

**原因**: `https://x.com/compose/post?text=...` 形式では `text` パラメータが無視されることがある

**解決策**: Twitter Web Intent形式を使用 → `https://twitter.com/intent/tweet?text={encoded_text}`

---

