# Marp Core browser usage

## 目次

- Marp Core（ブラウザ用）
  - 基本的な使い方
  - スライド表示
  - iOS Safari対応（必須）
  - Tailwind CSSとの競合
    - invertクラスの競合
    - 箇条書き（リストスタイル）の競合
  - SVGのレスポンシブ対応（スマホ対応）

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

**注意**: `list-style`（ショートハンド）ではなく `list-style-type`（個別プロパティ）を使うこと。ショートハンドだと `list-style-position` も暗黙的にリセットされ、テーマ側の設定が上書きされる。

```css
/* src/index.css に追加 */
.marpit ul {
  list-style-type: disc !important;
}

.marpit ol {
  list-style-type: decimal !important;
}

/* ネストされたリストのスタイル */
.marpit ul ul,
.marpit ol ul {
  list-style-type: circle !important;
}

.marpit ul ul ul,
.marpit ol ul ul {
  list-style-type: square !important;
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

---
