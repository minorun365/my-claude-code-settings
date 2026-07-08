# Tailwind CSS

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

