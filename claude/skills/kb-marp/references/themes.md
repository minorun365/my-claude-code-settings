# Marp custom themes

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
