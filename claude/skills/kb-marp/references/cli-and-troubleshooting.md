# Marp CLI, syntax, and troubleshooting

## 目次

- Marp CLI
  - 出力オプション
  - CodexでMarp CLIを実行するときの注意
  - LibreOffice (`soffice`) のインストール
    - macOS（Homebrew cask 経由が唯一の正解）
    - Docker / Linux
  - Docker環境でのPDF生成
- Marp記法の注意点
  - `==ハイライト==` 記法は使用禁止
- トラブルシューティング
  - スライドのCSSが適用されない
  - PDF出力でエラー
  - PDF日本語文字化け（豆腐文字）
  - 複数出力形式でテーマ設定が一部だけ反映される
  - カスタムテーマ: `position: absolute` が効かない（defaultテーマとの競合）
  - カスタムテーマ: 複数の `<p>` 要素が重なる
  - VSCode Marp プレビューで CSS の `url()` による背景画像が表示されない
    - 背景画像だけ出ない＝まず「テーマ登録の取りこぼし」を疑う（CLIで出るのにプレビューで出ない）
  - Marp で `<img style="width: %">` のサイズ指定が効かない
  - テーマ確認（デバッグ）
- 参考リンク

## Marp CLI

### 出力オプション

| オプション | 出力形式 | 依存 | 編集可能 |
|-----------|---------|------|---------|
| `--pdf` | PDF | なし | ❌ |
| `--pptx` | PPTX | なし | ❌ |
| `--pptx-editable` | PPTX（編集可能） | **LibreOffice必須** | ✅ |
| `--html` | HTML | なし | - |

### CodexでMarp CLIを実行するときの注意

Marp CLI の `--pdf` / `--pptx` / `--image` / `--images` は内部で Chrome/Puppeteer を起動する。Codex の通常サンドボックス内で試すと、macOS 側で「Google Chrome が予期しない理由で終了しました」のクラッシュレポートが出ることがある。

- CSS構文や背景画像の軽い確認だけなら、Chromeを起動しない `--html` 出力を優先する
- PDF/PPTX/画像出力が必要な場合は、通常権限で失敗させてから再実行せず、最初から権限つきで実行する
- `npx` で一時実行する場合は `npm_config_cache=/private/tmp/npm-cache-marp` のようにキャッシュを `/private/tmp` に逃がす

```bash
# 軽い確認（Chromeを起動しない）
marp --no-stdin --html --theme theme/custom.css --allow-local-files -o /private/tmp/check.html "slides/YYYY/YYYY-MM スライド名/スライド名.md"

# PDF/PPTX/画像の確認（Codexでは最初から権限つきで実行）
marp --no-stdin --pdf --theme theme/custom.css --allow-local-files -o /private/tmp/check.pdf "slides/YYYY/YYYY-MM スライド名/スライド名.md"
```

**注意**: `--pptx-editable` はLibreOfficeの `soffice` バイナリに依存する。Dockerコンテナ等でLibreOfficeがインストールされていない環境では以下のエラーが発生：

```
[EXPERIMENTAL] Converting to editable PPTX is experimental feature.
[ERROR] Failed converting Markdown. (LibreOffice soffice binary could not be found.)
```

→ LibreOffice不要な環境では `--pptx`（標準PPTX）を使用する。

### LibreOffice (`soffice`) のインストール

`--pptx-editable` を使う環境では事前に LibreOffice 本体（`soffice` CLI 含む）を入れておく。

#### macOS（Homebrew cask 経由が唯一の正解）

```bash
brew install --cask libreoffice
```

- ダウンロード約 280MB（DMG）、所要 3〜5 分。展開後 1.4GB+
- `/Applications/LibreOffice.app` 配置と同時に **`/opt/homebrew/bin/soffice` へシンボリックリンクが自動で張られる**ため、PATH 設定や `SOFFICE` 環境変数は不要
- 確認: `which soffice` → `/opt/homebrew/bin/soffice` / `soffice --version` → `LibreOffice X.X.X.X ...`
- 実体は `soffice.wrapper.sh` というラッパー経由で `/Applications/LibreOffice.app/Contents/MacOS/soffice` を起動する作り

⚠️ **DMG を手動マウントして `/Applications/` にドラッグした LibreOffice では PATH に通らない**ので、Marp が `soffice binary could not be found` で失敗する。必ず Homebrew cask 経由で入れること。

#### Docker / Linux

Debian / Ubuntu ベースなら apt で：

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-impress \
    && rm -rf /var/lib/apt/lists/*
```

- フル `libreoffice` パッケージは数百MB。`--pptx-editable` は Impress（プレゼンモジュール）だけで足りるので `libreoffice-impress` で軽量化できる
- `soffice` は `/usr/bin/soffice` に配置される

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
株式会社サンプル

テックエバンジェリスト　みのるん
```

**解決策**: `<br>` で結合して1つの `<p>` 要素にまとめる

```markdown
<!-- OK: 1つの<p>要素 -->
株式会社サンプル<br>テックエバンジェリスト　みのるん
```

**補足**: CSSの `flex-direction: column` を併用すると、`<br>` による改行が自然に縦に並ぶ

### VSCode Marp プレビューで CSS の `url()` による背景画像が表示されない

**症状**: フロントマターの `theme:` は効いていてフォント・色は反映されるが、テーマ CSS の `background-image: url('...')` で指定した背景画像が VSCode の Marp プレビューで表示されない（PDF エクスポートでは出る）

**原因**: VSCode Marp 拡張は CSS 内の `url()` を **md ファイルからの相対パス**として解決する（CSS ファイル基準ではない）。別リポからコピーした CSS は、元リポの md 階層を前提に url() が書かれているため、コピー先のリポでスライドを別階層に置くと届かない

**確認方法**: md ファイルから url() のパスをそのまま辿って、画像ファイルにたどり着けるか手計算する。たどり着けなければそのパスを修正する

**解決策**:

リポの「スライド md がリポルートからどれだけ深いか」と「`theme/image/` がリポルートからどれだけ深いか」に応じて、md からの相対で url() を書き直す。`slides/theme -> ../../theme` のようなシンボリックリンクを使えば、案件ディレクトリの構造変化を吸収できる。

**運用例**:

| リポ | md の位置 | シンボリックリンク | CSS の url() | 解決経路 |
|------|----------|------------------|--------------|---------|
| 例 | `marp/slides/YYYY/<スライド名>/<スライド名>.md`（深さ4） | `marp/slides/theme -> ../theme` | `url('../../theme/image/top.png')` | md から2階上 = `marp/slides/`、そこから `theme/image/`（シンボリック経由）= `marp/theme/image/` |

**ハマりポイント**:

- 別リポから CSS をコピーすると、url() パスがそのままだと階層が合わずに動かない。**CSS ファイル単体を見るのではなく、md ファイルから見た相対パス**で考える
- `./theme/image/...` という書き方は CSS 単体で見ると違和感がある（CSS が `theme/custom.css` なのに `./theme/image/` だと「`theme/theme/image/`?」と思える）が、これは md 基準で解決されるので正しい
- VSCode Markdown プレビューのセキュリティ設定を変更する必要はない（既定のままで動く）
- `.vscode/settings.json` の `markdown.marp.themes` でテーマ登録するか、リポルートに `.marprc.yml` で `themeSet` 指定するかのどちらかが必要。後者の方が**リポ全体で共有可能**で、各講師が個別設定する手間が省ける

#### 背景画像だけ出ない＝まず「テーマ登録の取りこぼし」を疑う（CLIで出るのにプレビューで出ない）

**症状**: フォント・色は効いてるのに背景画像（`top.png`/`crosshead.png` 等）だけ VSCode プレビューで出ない。**marp CLI でPDF化すると背景は正常に出る**。

**切り分け**: `npx -y @marp-team/marp-cli@latest --no-stdin --pdf --theme theme/custom.css --allow-local-files "<md>" -o /tmp/x.pdf` で出力 → 背景が出れば**ファイル・url()・シンボリックリンク・画像実体はすべて正常**。残る容疑者は **VSCode 側のテーマ登録**だけ。url() を base64 化したり書き換えたりして時間を溶かす前に、まずこのCLI切り分けをやる。

**根本原因**: `markdown.marp.themes` の登録は **VSCode で開いているワークスペースフォルダのルート基準**で解決される。work には登録用 `.vscode/settings.json` が**2か所**必要：

| VSCodeで開くフォルダ | 効く登録ファイル | `./theme/custom.css` の解決先 |
|---------------------|----------------|--------------------------|
| リポルート | `.vscode/settings.json` | `theme/custom.css` |
| サブフォルダ直開き | `<サブフォルダ>/.vscode/settings.json` | `<サブフォルダ>/theme/custom.css` |

`marp/.vscode/settings.json` が**誤って巻き込み削除**され、ルート側だけ残った。その結果「`marp/` を直接開くとテーマ未登録 → 背景だけ出ない」が**開くフォルダ次第で再発**した。両方に同内容（`./theme/custom.css` と `./theme/minorun-dark.css` を登録）を置いておくのが正解。直したら **VSCode をリロード**（`Developer: Reload Window`）しないとプレビューのキャッシュで反映されない。

**やってはいけない遠回り**:

- ❌ 背景画像を base64 でインライン展開する（不要・custom.css が肥大化する）
- ❌ CSS ファイル基準で url() を書き換える（解決ルールが違う）
- ❌ シンボリックリンクを使わずに `slides/theme/` 配下に CSS と画像を重複コピーする（既存運用に反する・メンテ箇所が増える）
- ❌ Web 検索結果の「VSCode Marp 拡張はローカル画像をブロックする」を真に受ける（誤情報・実際は適切なパスで普通に動く）

### Marp で `<img style="width: %">` のサイズ指定が効かない

**症状**: スライド本文中の画像を `<img src="..." style="display: block; margin: 0 auto; width: 45%;">` で配置したのに、`width` の % を変えても表示サイズが変わらない（VSCode Marp プレビューでも PDF 出力でも同じ）。

**原因**: Marp は `<section>` をスライドの container として描画し、内部的に flex レイアウトを適用する。この影響で HTML `<img>` の `style="width: N%"` 指定が **親要素のサイズと合わずに無視されたり、想定外の挙動になる**ことがある。`px` 単位の絶対指定でも反映されないケースがある。

**解決策**: Marp の **Markdown 画像構文 + 修飾子**に書き換える。Marp が直接処理するため、テーマや内部レイアウトに左右されずサイズが効く。

```markdown
<!-- ❌ NG -->
<img src="./image.png" style="display: block; margin: 0 auto; width: 45%;">

<!-- ✅ OK -->
![w:550 center](./image.png)
```

修飾子の詳細は「画像参照」セクションの「単一画像の中央配置とサイズ指定」を参照。

**ハマりポイント**:

- 「`width: 75%` から `45%` に減らしたのに見た目が変わらない」のは、そもそも HTML の style 属性が反映されていないだけで、最初から「テーマ既定のサイズ」が表示されていた可能性が高い
- `<style>` タグでクラス定義した CSS は効くが、`<img>` のインライン `style` 属性は効かないケースがあるため、確実なのは Marp Markdown 構文
- 複数画像の横並びレイアウト（flexbox）は `<style>` でクラス定義する従来の方法でOK（「複数画像を横並びにする」セクション参照）。単一画像の中央配置だけが Markdown 構文を推奨

**やってはいけない遠回り**:

- ❌ `width: 45%` → `width: 30%` のように % を小さくし続ける（そもそも反映されていない）
- ❌ `!important` を付けて style 属性を強化する（インライン style に `!important` は付けられない、かつ原因が違う）
- ❌ `.vscode/settings.json` のセキュリティ設定をいじる（無関係）

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
