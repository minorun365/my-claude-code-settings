# 外部ファイル受領時のワークフロー

事務局・主催者・取引先からファイル（Excel フォーム、PDF、Word、画像等）を渡されて編集する場合の標準ワークフロー。

## 基本方針

**Desktop / Downloads / Documents で直接編集しない。** プロジェクト配下にタスク用フォルダを作り、コピーしてから編集する（誤削除・誤上書き防止、原本バックアップ、git で履歴管理できる）。

## 標準フロー

1. **タスク用フォルダを作る**（例: `tasks/<案件名>/` 配下。提出物が増えた案件は独立ディレクトリへ昇格）
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

外部ファイルには以下が混入しがち。詳細は `/kb-xlsx` の「ファイル名・パスの罠」参照：

- シングルクォート U+2019（`'`）→ Bash・Python リテラル直書きで失敗する
- 全角括弧【】・全角スペース
- Excel 一時ロックファイル `~$<filename>.xlsx` → find / glob で除外する

```bash
# ✅ パス直書きせず glob / find で動的取得 + ロックファイル除外
SRC=$(ls /Users/.../Desktop/*<キーワード>*.xlsx 2>/dev/null | grep -v '~\$' | head -1)
```

## PDF はテキストレイヤー抽出を最優先

外部から受け取った PDF は、**マルチモーダル画像読み取りの前に必ずテキストレイヤー抽出を試す**。Excel / Sheets / Word / Marp / PowerPoint 由来の PDF はほぼ確実にテキストレイヤーが残っており、画像読みは数字・固有名詞・便名・口座番号の誤読リスクが高い。

```bash
python3 -c "
import fitz
doc = fitz.open('/path/to/file.pdf')
for i, page in enumerate(doc):
    print(f'=== PAGE {i+1} ===')
    print(page.get_text())
"
```

- PyMuPDF（`fitz`）は `anthropic-skills:pdf` 環境にも入っている
- スキャン PDF（OCR が必要なケース）だけ `Read` ツールの画像読み取りにフォールバック
- 構造が読みにくければ `page.get_text("dict")` で座標付き抽出

## アンチパターン

- ❌ Desktop / Downloads の元ファイルを直接編集（バックアップなし）
- ❌ 機密情報ありのファイルを `.gitignore` 未確認のまま push
- ❌ ファイルパスを Python リテラルに直書き（U+2019 で SyntaxError）
- ❌ Excel 一時ロックファイル `~$*.xlsx` をコピー（中身は空）
- ❌ 数字・固有名詞を含む PDF を画像読み取りだけで断定
