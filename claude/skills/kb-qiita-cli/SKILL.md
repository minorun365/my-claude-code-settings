---
name: kb-qiita-cli
description: Qiita CLI（@qiita/qiita-cli）の運用ナレッジ。共有リポジトリで個人記事流入を防ぐ .gitignore × シンボリックリンク方式、ファイル名規則、画像ホスティング選択、よくあるトラブル等。Qiita CLI を使うプロジェクトで自動発動。
model: sonnet
user-invocable: true
---

# Qiita CLI 運用ナレッジ

Qiita CLI（[increments/qiita-cli](https://github.com/increments/qiita-cli)）を使うプロジェクトでの運用パターンとハマりどころ。

## Qiita CLI の重要な制約

- 記事ファイルは **実行ディレクトリ直下の `public/` のみ**監視。サブディレクトリは完全に無視される
- `qiita pull` で取得した記事のファイル名は **`<Qiita ID>.md`（16進数20文字）** になる
- 記事の同一性は**フロントマターの `id`** で管理（ファイル名ではない）
- **画像アップロード機能はない**。Qiita Web エディタから手動アップロード or 外部ホスティング（S3 + CloudFront 等）で `https://` URL を埋め込む
- 記事の削除は CLI からできない（Qiita Web から削除）

## 共有リポジトリでの個人記事流入問題

複数人で使う Git リポジトリで Qiita CLI を運用する場合、各メンバーが `qiita pull` を打つと**個人の過去 Qiita 記事が全部 `public/` に降ってくる**。これを共有リポにコミットすると他メンバーに個人記事が混入する事故が起きる。

### 対策：`.gitignore` × シンボリックリンク方式

1. `qiita-cli/public/*.md` と `qiita-cli/public/picture` を **`.gitignore` で全除外**
2. 共有対象の原稿は**別の場所**（例: `projects/.../handson/`）に実体を置いて Git 管理
3. `qiita-cli/public/` から原稿実体へ**シンボリックリンク**を張る（リンク自体は ignore されるので各メンバーがローカルで作成）

```bash
# 例: チーム共有リポのパターン
cd qiita-cli/public
ln -s ../../projects/<案件>/handson/01-xxx.md .
ln -s ../../projects/<案件>/handson/picture .   # 案件1つ目だけ
```

Qiita CLI は Node.js の `fs` でファイルを読むため、**シンボリックリンクは透過的に扱われる**（preview / publish ともに正常動作）。

### ファイル名で個人記事と共有記事を見分ける

- **Qiita ID 形式**: `[0-9a-f]{20}\.md`（16進20文字）→ `qiita pull` で降ってきた個人記事
- **人間可読**: ハイフン区切りの説明的な名前 → 共有用に手で作った記事

`.gitignore` で `qiita-cli/public/*.md` と書くと両方除外できるが、もし「Qiita ID 形式だけ除外、人間可読は管理対象」にしたい場合は文字クラス20連で書く（ただしハイフン区切りなら混乱しない命名なので、全除外＋シンボリックリンクのほうがシンプル）。

## ファイル名規則のおすすめ

- **ハイフン区切り（kebab-case）** を採用。例: `01-environment-construction.md`
- アンダースコア（`_`）も Qiita CLI 上は動くが、Web/URL の標準慣習に合わせるならハイフン
- **半角スペース絶対NG**。URL で `%20` にエンコードされ、シェルでもクオート必須になり扱いづらい
- 章順を示すなら `01-`、`02-` のような数字 prefix を付ける

## 画像ホスティングの選択肢

Qiita CLI に画像アップロード機能がないため、3パターンから選ぶ：

1. **Qiita Web から手動アップロード** — 記事を一度 publish した後、Qiita Web エディタで画像を挿入。最も手間だが手軽
2. **S3 + CloudFront などの外部ホスティング** — `https://d1xxx.cloudfront.net/.../01-01-screenshot.png` のような URL を直接埋め込む。複数記事で再利用しやすい
3. **ローカル参照（プレビュー専用）** — `./picture/01-01-screenshot.png` を相対パスで書く。`npx qiita preview` では表示されるが、**publish しても Qiita 上では表示されない**

チーム共有リポでは 2 を採用。

## よく使うコマンド

```bash
cd qiita-cli                          # 以下はこのディレクトリ内で実行

npm install                           # 初回のみ
npx qiita login                       # アクセストークンを登録（~/.config/qiita-cli/ に保存）
npx qiita pull                        # Qiita → ローカルに同期
npx qiita new 記事名                  # 新規記事の雛形（public/ に生成。共有リポなら projects/ に移してリンクを張る）
npx qiita preview                     # http://localhost:8888 でプレビュー
npx qiita publish 記事名              # 特定記事を公開/更新
npx qiita publish --all               # 全記事一括（ignorePublish: true は除外）
```

## 公開状態（private）の切り替え

Qiita CLI の `publish` で公開状態を切り替えられるのは **新規 POST 時のみ**。既存記事への `PATCH`（更新）では、ローカルの `private` を変更しても Qiita 側の値で上書きされて元に戻る。

つまり：

- 新規記事を限定共有にしたい → 初回 publish 前にローカル md の `private: true` を書いておけば OK
- 既存記事の公開状態を変えたい → 以下のいずれか
  1. **Qiita Web 編集画面**で公開設定を変える（最も簡単）
  2. **Qiita Web で記事を削除** → ローカル md の `id` を `null`、`private` を希望値に戻して再 publish（新規 POST 扱いになり、`private` 指定が効く）。**ただし URL（記事ID）が変わる**
  3. Qiita API v2 を直接叩いて `PATCH /api/v2/items/{id}` で `private` を送る

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `unauthorized` | トークンのスコープが足りない（`read_qiita` と `write_qiita` 両方必要）か期限切れ。`npx qiita login` 再実行 |
| preview で画像が表示されない | シンボリックリンク `qiita-cli/public/picture` が無い or リンク先のファイルが消えている |
| publish しても Qiita 上で画像が見えない | ローカル相対パス（`./picture/xxx.png`）を使っている。外部 URL に書き換えるか Qiita Web で再アップロード |
| 他人のリポに自分の個人記事が混ざる | `.gitignore` に `qiita-cli/public/*.md` がない。本スキル冒頭の対策を参照 |
| 既存記事を `private: true` にしたのに切り替わらない | Qiita CLI の `PATCH` では `private` が反映されない仕様。上の「公開状態の切り替え」参照 |
| `ignorePublish: true` でも publish される | `npx qiita publish <記事名>` の個別指定は `ignorePublish` を無視する仕様。除外したいなら `--all` でのみ運用する |

## 関連実装

