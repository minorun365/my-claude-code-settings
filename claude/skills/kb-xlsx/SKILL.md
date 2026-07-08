---
name: kb-xlsx
description: Excelファイル(.xlsx)の読み書き・フォーム入力ナレッジ。事務局/主催者から届く「黄色マスに入力」型フォーム、openpyxl前提セットアップ、ファイル名特殊文字、チェック方式3パターン、anthropic-skills:xlsx 併用ノウハウ等。Excelの読み書きで詰まったとき・登壇/契約フォーム入力時に参照
model: sonnet
user-invocable: true
---

# Excel 操作ナレッジ

事務局・主催者から届く `.xlsx` フォーム入力や、Excel 読み書きで詰まったときの実戦知識集。

## 1. openpyxl のセットアップ

- 標準 macOS Python (`/usr/bin/python3`、3.9系) に **openpyxl は未インストール**
- まず入れる：`python3 -m pip install --user openpyxl`
- 編集時は **`load_workbook(path, data_only=False)`** で開く（`True` で開いて保存すると**数式が値に永久置換**されるので注意）

## 2. anthropic-skills:xlsx との使い分け

- 公式 `xlsx` スキルは `scripts/recalc.py`（LibreOffice 経由の数式再計算）を提供
- バージョンによっては `extract-text` コマンドが**実体に入っていない**ことがある → 無い場合は openpyxl で `iter_rows` 直読み
- 単純な値読み書き・既存フォーム入力なら openpyxl 直叩きが速い

## 3. ファイル名・パスの罠

- 主催者支給ファイルにはシングルクォート様記号 **U+2019 (`’`)** が混じることがある（例：`...DXPO東京’26【夏】.xlsx`）
- Bash の `ls` / `cat` 等に直渡しすると `No such file or directory` になる
- 対処：
  1. `find ~/Desktop -name "*<キーワード>*"` でフルパス取得
  2. Python なら `glob.glob("/Users/.../*<キーワード>*.xlsx")` で扱う
  3. Python 文字列リテラルにシングルクォートを含むパスを**直書きしない**（`SyntaxError`）→ `glob` か triple-quote
  4. `~$<filename>.xlsx` は Excel 編集中の一時ロック → 検索結果から除外する

## 4. 「黄色マスに入力」型フォームの読み解き

### 入力欄の判別

- 冒頭に「黄色く塗られているマスにご入力ください」と明記されたフォーム頻出
- `fill.fgColor.rgb == "FFFFFF00"` のセルが入力欄
- ただしテーマ色指定（`fg.type == "theme"`）の場合は `rgb` が `None` になる → 両方を判定

```python
for row in ws.iter_rows():
    for cell in row:
        if cell.fill.patternType == "solid":
            fg = cell.fill.fgColor
            if fg.type == "rgb" and fg.rgb == "FFFFFF00":
                print(cell.coordinate)
```

### チェック方式は基本「隣の専用セルに `✓`」

ほぼ全てのフォームでパターンAが採用される。`(黄色 AND 空セル)` がチェック/値の入力欄。

| パターン | 例 | 書き方 |
|---------|-----|--------|
| A. 隣の専用セルに `✓`（**推奨／ほぼ全フォームでこれ**） | `D41="✓"` + ラベル `E41="承諾する"`<br>`C44="✓"` + ラベル `B44="該当する"` | 空セル側に `"✓"` |
| C. 黄色マスに `✓` 単独（ラベル不要のチェック欄） | `A23="✓"` | そのまま `"✓"` |

### ⚠️ 致命的な罠：ラベルセルへの上書き禁止

**既存テキストが入っているセル（ラベル）を上書きしてはいけない。** 以下が頻発するNG パターン：

```python
# ❌ NG: ラベル「該当する」を「✓ 該当する」に上書き → ラベル破壊
ws["B44"] = " ✓     該当する"

# ✅ OK: 隣の空セルにチェック
ws["C44"] = "✓"  # B44 のラベルはそのまま
```

理由：
1. Excel **シート保護**がかかっているとGUIから元のラベルテキストを復元不可能（openpyxl でしか戻せない）
2. ラベル位置によっては印刷レイアウトが崩れる
3. 事務局側で原本テキストを再送してもらう必要が出る

**判定ロジック**:

```python
def find_input_cells(ws):
    """黄色 AND 空のセルを真の入力欄として抽出"""
    inputs = []
    for row in ws.iter_rows():
        for cell in row:
            f = cell.fill
            is_yellow = (
                f.patternType == "solid"
                and f.fgColor.type == "rgb"
                and f.fgColor.rgb == "FFFFFF00"
            )
            if is_yellow and cell.value is None:
                inputs.append(cell.coordinate)
    return inputs
```

### 「訂正欄」パターン — 既存値セルは絶対に上書きしない

事務局・主催者が**前回提出情報を転記**してくれているフォームで、その**直下のセル**に訂正記入欄が用意されているパターンが頻出。

```
Row N:   ラベル（"所属・役職"）| C11=既存値（事務局転記版）|
Row N+1:                       | C12="間違いがあればこちらにご記入ください" |
Row N+2: ラベル（"お名前"）    | C13=既存値（事務局転記版）|
Row N+3:                       | C14="間違いがあればこちらにご記入ください" |
```

ルール：

- **既存値セル（C11/C13/C15）は絶対に書き換えない** ← 上書きすると事務局原本が消える
- 訂正がある場合は**下のセル（C12/C14/C16）に訂正版を書く**
- 訂正がない場合は下のセルのガイダンス文「間違いがあればこちらにご記入ください」を**そのまま残す**（空欄扱いされる）

判定方法：

- 既存値セルの**直下のセル**に "間違いがあれば" "訂正" "修正" 等の文言があれば、そのセルが訂正欄
- 上の値セルが事務局転記版 / 下の値セルが訂正欄、というペアが成立しているか必ず確認する
- ガイダンス文セルはあえて黄色塗りされていないことが多い（「上書きされやすいから」あえて目立たないデザインの可能性）

### ラベルとペアの値欄を見抜く（merged_cells 活用）

`B36="会社名："`（薄い色） + `D36=（空・黄色・merged D36:M36）` のような構造：

- **B列＝ラベル**（薄い灰色 fill、テキスト入り）
- **D列以降＝値欄**（黄色 fill、空、結合セル）

書き込み前に**全セルを一覧化**：
```python
for row in ws.iter_rows():
    for cell in row:
        if cell.value is not None or is_yellow(cell):
            existing = "ラベル" if cell.value else "(空・入力欄)"
            print(f"{cell.coordinate}: {existing} -> {cell.value!r}")
```

ラベルが書かれているセルには絶対書き込まない。**書き込みは「空かつ黄色」のセルのみ**。

### ⚠️ フォームコントロール（VMLチェックボックス）は openpyxl 保存で全滅する

フォームに ☐Windows ☐Mac のような**チェックボックス（フォームコントロール）**が置かれている場合、`load_workbook()` → `save()` するだけで **`xl/drawings/vmlDrawing*.vml` と `xl/ctrlProps/*` が丸ごと削除され、チェックボックスが全部消える**。

**判別方法**：`unzip -l file.xlsx | grep -E "vmlDrawing|ctrlProp"` でヒットしたら openpyxl 保存は禁止。

**対処：ZIP内XMLの直接編集で値もチェックも書く**

1. セル値は `sheet1.xml` の空セル `<c r="C6" s="33"/>` を inlineStr に置換：
   `<c r="C6" s="33" t="inlineStr"><is><t xml:space="preserve">値</t></is></c>`（`xml.sax.saxutils.escape` でエスケープ）
2. チェック状態は2箇所セットで変更：
   - `vmlDrawing1.vml`：対象 `<v:shape>` の `<x:ClientData>` 直後に `<x:Checked>1</x:Checked>` を挿入
   - 対応する `ctrlProps/ctrlPropN.xml`：`objectType="CheckBox"` に `checked="Checked"` を追加
3. **シェイプ→ctrlProp の対応**：`sheet1.xml` の `<control shapeId="1035" r:id="rId5">` → `sheet1.xml.rels` で rId→ctrlPropN を解決。VMLシェイプ `id="_x0000_s1035"` の数字部分が shapeId と一致
4. **どのチェックボックスがどのラベルか**は VML の `<x:Anchor>`（colL,dxL,rowT,... の0始まり座標）とシェイプ内 `<div>` のラベルテキストで判別
5. 書き換えは `zipfile` で全エントリをコピーしつつ対象3種だけ差し替え（`ZIP_DEFLATED`）
6. 数式（文字数カウンタ等）のキャッシュ値が古くなるので、`workbook.xml` の `<calcPr>` に `fullCalcOnLoad="1"` を付けると Excel で開いた瞬間に再計算される

読み取り側の検証は openpyxl で普通にできる（load するだけなら壊れない。**save しなければOK**）。

## 5. 結合セル（merged_cells）

- 結合セルは**左上セルにだけ**値を書く（他に書くと openpyxl が警告 or 無視）
- `ws.merged_cells.ranges` で一覧確認
- フォームの送付先住所欄など、長文を入れる枠が結合されているケース多

## 6. シート名の末尾スペース問題

- 主催者作成シートで **シート名末尾に半角スペース** が入っていることがある（例：`"セミナー依頼同意書【要回答】 "`）
- `ws = wb["...】"]` でアクセスすると KeyError → 末尾の空白も含めた完全一致が必要
- `wb.sheetnames` を `repr()` で出力して空白を確認する習慣をつける
- Google Sheets でも類似の罠あり（work CLAUDE.md 参照）

## 7. バックアップと検証の鉄則

- **書き込み前にバックアップ**：`cp <src> tmp/<案件>-backup/original_$(date +%Y%m%d_%H%M%S).xlsx`
- **書き込み後に検証スクリプト**：`data_only=False` で読み直し、`expect in str(v)` で全項目を照合する
- 期待値が `None` の項目（空欄想定）も明示的に列挙して見落とし 0 件にする
