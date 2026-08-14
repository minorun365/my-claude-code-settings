# 外部ファイル受領時のワークフロー

事務局・主催者・取引先からファイル（Excel フォーム、PDF、Word、画像等）を渡されて編集する場合の標準ワークフロー。

## 基本方針

**Desktop / Downloads / Documents で直接編集しない。** プロジェクト配下にタスク用フォルダを作り、コピーしてから編集する（誤削除・誤上書き防止、原本バックアップ、git で履歴管理できる）。

## 標準フロー

1. **タスク用フォルダを作る**（`tasks/{カテゴリ}/{案件名}/` のような配下。提出物が増えた案件は独立ディレクトリへ昇格）
2. **元ファイルをそのフォルダにコピー**（`original.*` として原本を残す）
3. **コピーを編集**（`edited.*` → 提出版は `final.*`。Desktop の元ファイルは触らない）
4. **編集後に保存先パスを明示して案内**

推奨構成：`README.md`（案件概要）+ `form/`（original / edited / final）+ `attachments/`

## 機密情報の扱い

| 機密度 | 例 | 対処 |
|--------|---|------|
| 公開可 | 会社住所・代表者名（Web 掲載済み） | コミット OK |
| 社内既知 | 電話番号・所属 | プロジェクトポリシーに従う |
| 個人情報 | 生年月日・口座情報等 | **`.gitignore` で除外** |
| 取引先・顧客情報 | 顧客名・契約条件等 | 案件ごとに判断、迷ったら除外 |

迷ったら **`.gitignore` 除外を選ぶ**（必要なら後で `git add -f`）。`tasks/*/form/` のような汎用パターンで除外推奨。

## ZIP 展開は `ditto` を使う（日本語ファイル名の文字化け防止）

macOS 標準の `unzip` は ZIP 内の UTF-8 ファイル名を壊すことがある。

```bash
# ✅ ditto で UTF-8 保持して展開（-V:詳細 -x:展開 -k:ZIP形式）
ditto -V -x -k foo.zip dest/
```

展開後は `ls dest/ | head -3` でファイル名が日本語のまま見えるか確認（`?????` なら失敗）。

## ファイル名・パスの罠

外部ファイルには以下が混入しがち：

- シングルクォート U+2019（`'`）→ Bash・Python リテラル直書きで失敗する
- 全角括弧【】・全角スペース
- Excel 一時ロックファイル `~$<filename>.xlsx` → find / glob で除外する
- **macOS のファイル名は NFD 正規化**（濁点・半濁点が分解されている）。ファイル名をコピペした Markdown 行は、見た目が同じでも Edit / apply_patch の完全一致置換にマッチしないことがある。ファイル名を含む行の編集は、①ファイル名を含まない近傍行をアンカーにする、②行番号ベースで Python / sed により挿入・置換する、のどちらかで回避する

```bash
# ✅ パス直書きせず glob / find で動的取得 + ロックファイル除外
SRC=$(ls ~/Desktop/*<キーワード>*.xlsx 2>/dev/null | grep -v '~\$' | head -1)
```

## PDF はテキストレイヤー抽出を最優先

外部から受け取った PDF は、**マルチモーダル画像読み取りの前に必ずテキストレイヤー抽出を試す**。Excel / Sheets / Word / Marp / PowerPoint 由来の PDF はほぼ確実にテキストレイヤーが残っており、画像読みは数字・固有名詞・便名・口座番号の誤読リスクが高い。

```bash
# テキストレイヤーの有無をまず判定する
pdftotext -layout /path/to/file.pdf - | head -40
```

- **このMacの system python3 に PyMuPDF（`fitz`）は入っていない。** `import fitz` は `ModuleNotFoundError` で落ち、`pip install --user` も PEP 668（externally-managed-environment）で拒否される。**入っている前提のコードを書かない**。`anthropic-skills:pdf` スキルを起動した場合はそのスキルの環境で使えることがあるが、素の Bash からは使えない
- ✅ **回避策は `uv run --with <パッケージ> python - <<'PY' … PY`。** 一時環境を作って実行するので PEP 668 を踏まない。`fitz`（PyMuPDF）でも `python-pptx` でも `boto3` でも同じ形で使える。ただし**まず poppler / mupdf の CLI で代替できないかを見て、Python ライブラリでしか書けないときだけ使う**
- 代わりに Homebrew 導入済みの poppler / mupdf を使う。テキスト抽出は `pdftotext -layout`、座標付きの構造は `mutool draw -F stext`、画像化は `pdftoppm -png -r 150`
- **スキャン PDF（手書きの赤入れなど、テキストレイヤーが無いもの）** は `mutool draw -r 150 -o p%02d.png <file>.pdf` で全ページ PNG 化して `Read` で画像読解する。薄い赤字など判読しにくいページだけ `-r 300` で再レンダリングして拡大確認する

## 日本語PDFを生成するときはフォントを先に決める

reportlab 等で日本語PDFを生成するときは、着手前にフォントを決めておく。フォント選定（ヒラギノは埋め込めない・BIZ UDゴシックを使う）、ユーザー好みの配布用体裁、フォント名3系統の指定方法と `pdffonts` での埋め込み機械確認がそこにある。

## YAML への追記は、クォートと機械検証をセットにする

- **URL やコロンを含む値は必ずダブルクォートで囲む。** 特にフロー配列（`[a, b, c]`）の中の裸URLは `found unexpected ':' while scanning a plain scalar` でファイル全体がパース不能になる
- **このMacの system python3 に PyYAML は入っていない**（`fitz` が無いのと同じ系統の罠）。検証は ruby で行い、追記したら必ず1回通す

```bash
ruby -ryaml -e 'YAML.load_file(ARGV[0])' <file>.yaml
```

**`-e` の中身に日本語を1文字でも入れると `invalid multibyte char (US-ASCII)` で落ちる。** Ruby の `-e` はマジックコメントが無いと US-ASCII 扱いになり、上のコマンドが通るのは ASCII だけだから。成功メッセージを足すなら英数字だけにする（`puts "YAML OK"`）か `ruby -E UTF-8` を付ける。

## アンチパターン

- ❌ Desktop / Downloads の元ファイルを直接編集（バックアップなし）
- ❌ 機密情報ありのファイルを `.gitignore` 未確認のまま push
- ❌ ファイルパスを Python リテラルに直書き（U+2019 で SyntaxError）
- ❌ Excel 一時ロックファイル `~$*.xlsx` をコピー（中身は空）
- ❌ 数字・固有名詞を含む PDF を画像読み取りだけで断定
