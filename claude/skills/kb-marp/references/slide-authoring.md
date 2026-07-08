# Marp slide authoring guide

## 目次

- Marpスライド作成ガイド（共通ルール）
  - 新規スライドの作成
  - 画像参照
    - 単一画像の中央配置とサイズ指定（推奨：Marp Markdown 構文）
    - HTML `<img>` ではなく Markdown 構文を使う理由
  - 共通テーマクラス
  - スライド固有のスタイルカスタマイズ
    - 基本ルール
    - なぜこの方法か
    - 複数画像を横並びにする（flexbox）
    - 特定要素だけスタイルを変えたい場合
    - 特定スライドだけスタイルを変えたい場合（scoped）
    - 実用パターン：画像を右下に絶対配置、テキストを左に流す
  - 素材管理運用
    - 画像の元ファイル（編集可能な原本）も `images/` に置く
    - 過去スライドから画像を再利用する
  - スライドのテキストスタイル
  - 情報密度
  - コマンド
    - PDF出力（VS Code Marp拡張）
    - Marp CLI

## Marpスライド作成ガイド（共通ルール）

複数のMarpスライドリポジトリで共通して適用されるルール。

### 新規スライドの作成

1. `slides/` または `slides/YYYY/` 配下に `YYYY-MM スライド名` 形式でフォルダを作成
2. フォルダ内にマークダウンファイルを作成
3. 以下のフロントマターで開始：

```markdown
---
marp: true
paginate: true
theme: テーマ名
---
```

各フォルダには以下を配置：
- マークダウンファイル（スライド本体）
- 画像ファイル（スライド固有のもの）
- 関連資料（検討メモ、参考資料など）

### 画像参照

スライド内の画像は同じフォルダに置き、相対パスで参照：

```markdown
![bg right:33% contain](./画像名.jpg)
```

#### 単一画像の中央配置とサイズ指定（推奨：Marp Markdown 構文）

スライド本文中に **1枚の画像を中央寄せで配置**する場合、HTML の `<img style="width: ...">` ではなく **Marp の Markdown 画像構文 + 修飾子** を使う。

```markdown
![w:600 center](./画像名.png)
```

| 修飾子 | 効果 |
|--------|------|
| `w:600` | 幅 600px に指定（`width:600` も可） |
| `h:300` | 高さ 300px に指定 |
| `center` | 中央寄せ |
| `left` / `right` | 左寄せ / 右寄せ |

**サイズ感の目安**（標準スライド幅 1280px、本文エリア約 1100px）:

- 控えめ（テキスト併存）: `w:500` 〜 `w:700`
- バランス重視: `w:800` 〜 `w:950`
- スライド全面（大きめ画像メイン）: `w:1000` 〜 `w:1150`

#### HTML `<img>` ではなく Markdown 構文を使う理由

HTML タグで書くと `style="width: 45%"` のような **% 指定がうまく効かない**ケースがある（Marp が `<section>` を flex container 化する関係で、style 属性のサイズ指定が無視される）。

```markdown
<!-- ❌ NG: width: 45% にしても変わらないことがある -->
<img src="./image.png" style="display: block; margin: 0 auto; width: 45%;">

<!-- ✅ OK: Marp が直接処理するので確実に効く -->
![w:550 center](./image.png)
```

詳細はトラブルシューティング「Marp で `<img style="width: %">` のサイズ指定が効かない」を参照。

### 共通テーマクラス

| クラス | 用途 |
|-------|------|
| `top` | タイトルスライド（中央寄せ、ページ番号非表示） |
| `crosshead` | セクション区切り（中央寄せ、ページ番号非表示） |

```markdown
<!-- _class: top -->
# タイトル
```

### スライド固有のスタイルカスタマイズ

テーマを使用しつつ、特定のスライドだけスタイルを変更したい場合のルール。

#### 基本ルール

1. `<style>`タグをフロントマターの直後に配置
2. 絶対値（pt）で指定（em や % は避ける）
3. `!important`を付けてテーマを上書き

```markdown
<style>
h1 { font-size: 36pt !important; }
p, li { font-size: 22pt !important; }
</style>
```

#### なぜこの方法か

| 方法 | 結果 |
|------|------|
| フロントマターの `style:` | テーマとの相性で表示されないことがある |
| em / % での相対指定 | テーマの基準値と合わず予期しないサイズになる |
| `<span style="...">` 等のインラインスタイル | Marpがセキュリティ上サニタイズするため無視される |
| `<style>`タグ + pt + !important | 確実にテーマを上書きできる |

#### 複数画像を横並びにする（flexbox）

画像を横に並べたい場合、インライン `style` 属性はサニタイズされて無効になる。
`<style>` タグでクラスを定義し、`class` 属性で指定すること。

> 例: CSSバーチャート（`<span class="bar" style="width: 76%">`）でバーが丸ごと消えた。棒ごとに幅が違う場合も `.bar.w1 { width: 76%; }` のように幅クラスを scoped CSS に定義して `class="bar w1"` で指定すれば正しく描画される。数字カード・枠マップ・レイヤー図などの div ベース図解も同様に「スタイルは全部 `<style scoped>`、HTML側は class のみ」で作る。

```markdown
<style>
.img-row { display: flex; gap: 6px; width: 100%; }
.img-row img { width: calc(25% - 5px); height: 420px; object-fit: cover; object-position: center; border-radius: 8px; }
</style>

<div class="img-row">
<img src="./image1.png">
<img src="./image2.png">
<img src="./image3.png">
<img src="./image4.png">
</div>
```

- `object-fit: cover` + `object-position: center` で中央クロップ表示
- 縦長画像を横幅100%で並べる場合は高さ固定でcoverが適切
- `height` は利用可能なスペースに応じて調整する

#### 特定要素だけスタイルを変えたい場合

`<style>` タグでカスタムクラスを定義し、HTML タグの `class` 属性で適用する。

```markdown
<style>
.name { font-size: 30pt !important; font-weight: bold !important; color: #ffffff !important; }
</style>

<span class="name">@minorun365</span>
```

Marp はインラインの `style` 属性（`<span style="...">`）をサニタイズして無視するため、必ず `<style>` タグ + `class` 属性の組み合わせで使うこと。

#### 特定スライドだけスタイルを変えたい場合（scoped）

`<style scoped>` を使うと、そのスライドだけにスタイルを適用できる。

```markdown
<style scoped>
p { font-size: 36pt !important; }
</style>
```

#### 実用パターン：画像を右下に絶対配置、テキストを左に流す

スクショを入れたいけど、箇条書きや本文も同じスライド内に欲しいとき。
`<style scoped>` + `position: absolute` で画像を右下に固定して、
左の領域にテキストを自然に流す。

```markdown
<style scoped>
.rb-img {
  position: absolute;
  right: 50px;
  bottom: 50px;
  width: 700px;
}
</style>

# スライドタイトル

左に流れるテキスト
箇条書きも自由に入れられる

<img src="./images/screenshot.png" class="rb-img">
```

- `right` / `bottom`: パディング調整可能（30〜80pxが目安）
- `width`: 画像サイズ（400〜800pxで適宜）
- **画像は `<img src="..." class="...">` 形式で書く**。`![center](...)` 構文はクラス属性を付けられないので使えない

### 素材管理運用

#### 画像の元ファイル（編集可能な原本）も `images/` に置く

PowerPointやKeynoteで作った図を `.png` で書き出してスライドに使う場合、
元の `.pptx` や `.key` ファイルも同じ `images/` に置いておくと、
後から微修正したいときに再編集できる。

```
images/
├── registry.png      # Marpで参照する書き出し画像
└── Tech Lead.pptx    # 書き出し元の編集可能な原本（Marpからは参照しない）
```

Marpは参照されていないファイルを無視するので、原本を一緒に置いても動作には影響しない。
PDF/PPTX書き出し時も原本は含まれない。

#### 過去スライドから画像を再利用する

登壇スライドリポジトリ（`marp-slides` 等）の過去スライドを
再利用素材の引き出しとして使うワークフロー。

```bash
# 過去スライドから画像を探す
find slides -iname "findy*"
find slides -iname "*<イベント名>*"

# 見つけたら現スライドのimages/にコピー
cp "slides/<年月 イベント名>/images/findy.png" "slides/<年月 新スライド>/images/"
```

スライド本体の md ファイルを grep で検索して、過去どのスライドでどう使われたかも
確認できる：

```bash
grep -rn "findy" slides/ --include="*.md"
```

### スライドのテキストスタイル

AIっぽい文章にしないこと。以下のルールを厳守する。

- 本文中に太字（`**...**`）を多用しない。強調したい場合でもベタ書きで十分
- コロン（`:`）を区切りとして使わない（例: `**項目名**: 説明文` はNG）
- ダッシュ（`──`）を使わない
- 箇条書きの項目は「太字ヘッダー + コロン + 本文」ではなく、本文のみベタ書きにする
- 箇条書き・表・コードブロックの後にテキストを続ける場合は `<br>` タグを1つ挟んで行間を空ける
- アジェンダスライドは設けない
- まとめスライドも設けない（限られた時間を中身に集中させるため）

### 情報密度

- 1スライド1メッセージを徹底
- 箇条書きは3-4項目が上限、1項目1-2文
- 箇条書きの階層は基本1階層（深くても2階層まで）
- 段階的ビルドアップ（同じスライドを複数枚用意し、要素を1つずつ追加して理解を積み上げる）

### コマンド

#### PDF出力（VS Code Marp拡張）

1. `⌘+⇧+P` → 「Marp: Export Slide Deck」を選択
2. 出力形式（PDF/HTML/PPTX）を選ぶ

#### Marp CLI

```bash
# インストール
npm install -g @marp-team/marp-cli

# PDF出力（ローカル画像を含む場合は --allow-local-files が必須）
marp slides/XXX/XXX.md --pdf --theme theme/テーマ名.css --allow-local-files
```

---
