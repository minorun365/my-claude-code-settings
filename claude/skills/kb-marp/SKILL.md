---
name: kb-marp
description: Marp（スライド生成）のナレッジ。Marp Core/テーマ/iOS対応/PDF生成/CLI等
user-invocable: true
---

# Marp（スライド生成）ナレッジ

Marp（Markdown Presentation Ecosystem）を使ったスライド生成に関する学びを記録する。

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

## カスタムテーマ

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

### テーマ統一ディレクティブ（テーマ切り替え互換性）

複数テーマ間で切り替え可能にするため、全テーマで統一されたCSSクラスベースのディレクティブを使う。デザイン差はCSSのみで吸収する。

| 用途 | ディレクティブ |
|------|-------------|
| タイトルスライド | `<!-- _class: lead --><!-- _paginate: skip -->` |
| セクション区切り | `<!-- _class: lead -->` |
| 参考文献スライド | `<!-- _class: tinytext -->` |

**NG**: テーマ固有のインラインスタイル（`<!-- _backgroundColor: #303030 --><!-- _color: white -->`）はテーマ切り替え時に崩れる。

**フロントエンドの正規化**: 旧スタイルの既存スライドは `SlidePreview.tsx` の `useMemo` 内で自動的に統一クラスに変換する。

### Gaiaベーステーマの注意（Speee等）

`@import "default"` を使わないGaiaベースのテーマは、リスト余白やビュレット位置のデフォルトスタイルが欠落する。以下を明示的に設定する：

```css
ul, ol {
  padding-left: 0;
  list-style-position: inside;  /* ビュレットをテキスト開始位置に揃える */
  margin-top: 0.6em;            /* 見出し・テキストとの余白 */
}
ul ul, ul ol, ol ul, ol ol {
  padding-left: 1.5em;
  margin-top: 0;
}
```

### フロントエンドとバックエンドの両方に配置

カスタムテーマを使う場合、以下の両方に配置が必要:
- `src/themes/xxx.css` - フロントエンド（Marp Core）用
- `amplify/agent/runtime/xxx.css` - バックエンド（Marp CLI PDF生成）用

PDF生成時は `--theme` オプションでCSSファイルを指定:
```python
cmd = ["marp", md_path, "--pdf", "--theme", str(theme_path)]
```

---

## Marp CLI

### 出力オプション

| オプション | 出力形式 | 依存 | 編集可能 |
|-----------|---------|------|---------|
| `--pdf` | PDF | なし | ❌ |
| `--pptx` | PPTX | なし | ❌ |
| `--pptx-editable` | PPTX（編集可能） | **LibreOffice必須** | ✅ |
| `--html` | HTML | なし | - |

**注意**: `--pptx-editable` はLibreOfficeの `soffice` バイナリに依存する。Dockerコンテナ等でLibreOfficeがインストールされていない環境では以下のエラーが発生：

```
[EXPERIMENTAL] Converting to editable PPTX is experimental feature.
[ERROR] Failed converting Markdown. (LibreOffice soffice binary could not be found.)
```

→ LibreOffice不要な環境では `--pptx`（標準PPTX）を使用する。

### Docker環境でのPDF生成

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
```

**ポイント**:
- `chromium` - PDF生成に必須
- `fonts-noto-cjk` - 日本語の豆腐文字（□）防止

---

## Marp記法の注意点

### `==ハイライト==` 記法は使用禁止

Marpの `==テキスト==` ハイライト記法は、日本語のカギカッコと組み合わせるとレンダリングが壊れる。

```markdown
<!-- NG: 正しく表示されない -->
==「重要」==

<!-- OK: 太字を使う -->
**「重要」**
```

LLMにスライド生成させる場合は、システムプロンプトで禁止指示を入れておくこと。

---

## トラブルシューティング

### スライドのCSSが適用されない

**症状**: スライドのスタイルが正しく表示されない

**原因**: `section`要素だけを抽出してDOM構造が崩れた

**解決策**: SVG要素をそのまま使い、`div.marpit`でラップする
```tsx
<div className="marpit">
  <div dangerouslySetInnerHTML={{ __html: svg.outerHTML }} />
</div>
```

### PDF出力でエラー

**症状**: Dockerコンテナ内でPDF生成に失敗

**原因**: Chromiumがインストールされていない

**解決策**: Dockerfileに追加
```dockerfile
RUN apt-get update && apt-get install -y chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
```

### PDF日本語文字化け（豆腐文字）

**症状**: PDFをダウンロードすると日本語が□（豆腐）で表示される

**原因**: Dockerコンテナに日本語フォントがない

**解決策**: Dockerfileに日本語フォントを追加
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv
```

### 複数出力形式でテーマ設定が一部だけ反映される

**症状**: PDF出力では正しいテーマが適用されるが、PPTX出力では常に同じテーマが使われる

**原因**: 出力形式ごとに別関数を作成した際、一方の関数でテーマをハードコードしていた

**解決策**: すべての出力関数で環境変数を一貫して使用する

```python
THEME_NAME = os.environ.get("MARP_THEME", "border")

def generate_pdf(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / f"{THEME_NAME}.css"
    ...

def generate_pptx(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / f"{THEME_NAME}.css"  # 同じ方式に統一
    ...
```

### カスタムテーマ: `position: absolute` が効かない（defaultテーマとの競合）

**症状**: カスタムテーマで `section.top p { position: absolute; bottom: 0; left: 0; width: 100%; }` を設定しても、p要素が意図した位置に配置されない（右に寄る等）

**原因**: `@import 'default'` で読み込まれるMarpデフォルトテーマのスタイルが、カスタムテーマのスタイルと競合して上書きされる

**解決策**: 位置・レイアウト系プロパティに `!important` を追加して確実に適用

```css
section.top p {
  position: absolute !important;
  bottom: 0 !important;
  left: 0 !important;
  width: 100% !important;
  height: 33% !important;
  display: flex !important;
  flex-direction: column;
  align-items: center !important;
  justify-content: center !important;
  margin: 0 !important;
  text-align: center;
  box-sizing: border-box;
  z-index: 1;
}
```

**教訓**: `@import 'default'` を使うカスタムテーマでは、レイアウト系プロパティ（position, display, margin等）に `!important` を付けないとデフォルトテーマに負ける場合がある

### カスタムテーマ: 複数の `<p>` 要素が重なる

**症状**: タイトルスライドで所属と名前を空行で分けて書くと、2つのp要素が同じ位置に重なって表示される

**原因**: Markdownで空行を挟むと別々の `<p>` 要素になる。`position: absolute` で同じ座標に配置されるため重なる

```markdown
<!-- NG: 2つの<p>要素が生成される -->
KDDIアジャイル開発センター株式会社

テックエバンジェリスト　みのるん
```

**解決策**: `<br>` で結合して1つの `<p>` 要素にまとめる

```markdown
<!-- OK: 1つの<p>要素 -->
KDDIアジャイル開発センター株式会社<br>テックエバンジェリスト　みのるん
```

**補足**: CSSの `flex-direction: column` を併用すると、`<br>` による改行が自然に縦に並ぶ

### テーマ確認（デバッグ）

スライドに適用されているテーマを確認するには、ブラウザDevToolsで:
```javascript
// section要素のdata-theme属性を確認
document.querySelectorAll('section[data-theme]')
```

---

## 参考リンク

- [Marp 公式](https://marp.app/)
- [Marp Core](https://github.com/marp-team/marp-core)
- [Marp CLI](https://github.com/marp-team/marp-cli)
- [Marp コミュニティテーマ](https://rnd195.github.io/marp-community-themes/)
- [marpit-svg-polyfill](https://github.com/marp-team/marpit-svg-polyfill)
