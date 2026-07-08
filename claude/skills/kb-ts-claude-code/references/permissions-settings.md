# Permissions, settings, skills, and rules

## 目次

- permissions: Bash コマンドの自動承認が `&&`/`||` 連結で機能しない
- permissions の設計原則（公式ドキュメントより）
- CLAUDE.md の階層構造
- settings.json の同期対象と非同期対象
- CLAUDE.md / Skills / Agents 最適化パターン（2026年4月検証済み）
  - settings.json の `rules` フィールドは存在しない
  - エージェント description は毎セッション表示される → 短くすべき
  - Skills の frontmatter description も毎セッション表示される
  - プロジェクトスコープ Skills の活用
  - CLAUDE.md 最適化の原則
- rules ファイルの `paths:` frontmatter でコンテキストを節約する
  - 問題
  - 解決策
  - 効果の目安
- skill / rules / CLAUDE.md の責務分離
- SKILL.md の frontmatter タイポ: `user-invokable` → `user-invocable`
  - 問題
  - 確認コマンド
- スキルの retire（廃止）判断基準
  - 判断フロー
- ローカル Git リポジトリの棚卸しコマンド集
  - 全リポジトリの最終コミット日・状態を一覧表示
  - Git リポジトリでないディレクトリ（タイムスタンプ確認）
  - 未プッシュコミットの確認
  - ディスク使用量の降順確認
- プッシュ可否の判断チェックリスト
  - よくある「プッシュ不要」パターン

## permissions: Bash コマンドの自動承認が `&&`/`||` 連結で機能しない

**症状**: `diff ... && echo "差分なし" || echo "差分あり"` のような複合コマンドで、`allow` に `Bash(diff *)` があるのに承認プロンプトが表示される

**原因**: Claude Code の Bash パーミッション評価はシェルオペレータ（`&&`、`||`）を認識しており、プレフィックスマッチルール（例：`Bash(safe-cmd *)`）は `safe-cmd && other-cmd` 形式の複合コマンドにはマッチしない（公式ドキュメント明記）

**解決策**: `allow` に `Bash(*)` を追加して全 Bash コマンドを自動承認し、手動承認が必要なコマンドのみ `deny` リストに追加する

```json
// ~/.claude/settings.json
{
  "permissions": {
    "allow": [
      "Bash(*)",        // 全 Bash コマンドを自動承認
      "WebSearch",
      "WebFetch",
      "Read", "Glob", "Grep"
    ],
    "deny": [
      "Bash(git push*)"  // push のみ手動承認
    ],
    "defaultMode": "default"  // Write/Edit 等は引き続き手動承認
  }
}
```

**ルール評価順序**: `deny` → `allow` → `defaultMode` の順で評価。`deny` が最優先なので、`Bash(*)` で全許可しつつ `deny` で特定コマンドだけ遮断できる。

**重要**: `Write` / `Edit` ツールは Bash と独立して評価されるため、`Bash(*)` を許可してもファイル編集ツールは `defaultMode` に従って手動承認のまま維持される。

---

## permissions の設計原則（公式ドキュメントより）

- `Bash(cmd *)` は単純なコマンドにのみ有効。`&&` / `||` で繋がれた複合コマンドにはマッチしない
- 引数パターンマッチング（例：`Bash(curl http://github.com/ *)`）は脆弱。オプション順序変更・変数展開・プロトコル変更などで簡単に回避される
- `Bash(*)` ≡ `Bash`（省略形、全 Bash コマンド許可と等価）
- **推奨設計**: 細かい `allow` パターンより `Bash(*)` + `deny` リストのほうが確実で保守しやすい

---

## CLAUDE.md の階層構造

Claude Code は複数の階層の `CLAUDE.md` を自動読み込みする：

| ファイル | スコープ | 用途 |
|---------|---------|------|
| `~/.claude/CLAUDE.md` | グローバル | 全セッション共通の行動指針 |
| `~/CLAUDE.md` | ホームディレクトリ | ホーム起動時のナビゲーション・横断作業ガイド |
| `~/git/<repo>/CLAUDE.md` | リポジトリ | プロジェクト固有の指示・技術スタック |

**ポイント**: 下位（リポジトリ）の設定が上位を上書きするのではなく、**すべて読み込まれて累積**される。

---

## settings.json の同期対象と非同期対象

端末間で `settings.json` を同期する際、以下を区別する：

**同期すべき項目**（端末間で共通化したいもの）：
- `permissions.allow` / `permissions.deny` / `permissions.defaultMode`
- `spinnerVerbs`（カスタム表示文字列）
- `language`（言語設定）

**同期すべきでない項目**（PC固有のもの）：
- `hooks`（スクリプトのパスが OS・PC 依存）
- `statusLine`（パス依存）
- `model`（セッションごとに変わる）

---

## CLAUDE.md / Skills / Agents 最適化パターン（2026年4月検証済み）

### settings.json の `rules` フィールドは存在しない

Claude Code の `settings.json` スキーマには `rules` フィールドが定義されていない。追加しようとするとバリデーションエラーになる。

```
Settings validation failed:
- : Unrecognized field: rules
```

短い行動ルールは CLAUDE.md に書くこと。

### エージェント description は毎セッション表示される → 短くすべき

`~/.claude/agents/*.md` の frontmatter `description` は **毎セッションのスキル一覧 (system-reminder) に全文表示**される。description が長いほどトークンを消費する。

**推奨**: 1-2行（100文字以内）に絞る。`<example>` XML などの使用例は description には不要（エージェント本文 `---` 以降に書けば十分）。

```yaml
# NG: 1200文字の description（使用例XMLを4つ埋め込み）
description: "Use this agent when... <example>...</example><example>...</example>..."

# OK: 1-2行に絞る
description: "アプリのテスト・デバッグ・ログ調査エージェント。Chrome DevTools/Playwright/CloudWatch担当。"
```

### Skills の frontmatter description も毎セッション表示される

SKILL.md の frontmatter `description` も system-reminder に表示される。ただし **Skills 本文はオンデマンド**（呼び出し時のみ）なのでコスト低。description は1行で簡潔に。

### プロジェクトスコープ Skills の活用

グローバルスキル（`~/.claude/skills/`）にしか入れられないと思いがちだが、**プロジェクト固有スキルは `.claude/skills/` に置ける**。

```
<repo>/.claude/skills/<skill-name>/SKILL.md
```

- グローバルと同じ frontmatter 形式で使える
- そのリポジトリで作業中のセッションでのみスキル一覧に表示される
- 書籍専用・プロジェクト専用スキルはここに置くとグローバルのノイズを減らせる

### CLAUDE.md 最適化の原則

CLAUDE.md に書く内容は「**ほぼ毎セッションで必要なもの**」に限定する。

| 書く場所 | 基準 |
|---------|------|
| CLAUDE.md | 毎セッション必要（ユーザー情報、コアルール、重要ワークフロー） |
| Skills | 特定トピック作業時のみ必要（技術ナレッジ、トラブルシューティング） |
| memory/ | 頻繁に更新されるデータ（プロジェクト一覧等） |

**目安**: グローバル CLAUDE.md は 200行以内に収めるとコンテキスト効率が良い。

---

## rules ファイルの `paths:` frontmatter でコンテキストを節約する

### 問題

`.claude/rules/` 配下のファイルに `paths:` frontmatter がないと、**全ての会話・全てのファイル編集で常に読み込まれる**。大きな rules ファイルが複数あると、コンテキストウィンドウが無駄に消費される。

### 解決策

`paths:` に glob パターンを指定すると、**そのパターンに一致するファイルを編集・参照しているときだけロードされる**。

```yaml
---
paths:
  - "drafts/**"           # 下書き作業時のみ読み込む
---

# PDF編集ルール
...
```

| rules ファイルの用途 | 推奨 paths パターン |
|---------------------|------------------|
| 特定ディレクトリの編集ルール | そのディレクトリの glob |
| PR レビュー時の手順 | 作業対象ディレクトリの glob を広めに指定 |
| 全会話で常に参照したいルール | `paths:` を省略（常時ロード） |

### 効果の目安

300行の rules ファイル × 2個 = **約600行（≈6,000トークン）を毎回節約**できる。長い会話セッションでのコンテキスト管理に効果大。

---

## skill / rules / CLAUDE.md の責務分離

| ファイル | 責務 | 使い分け |
|---------|------|---------|
| `CLAUDE.md` | 常時参照すべきプロジェクト概要・原則 | 短く概要のみ。詳細は rules/skill に委譲 |
| `.claude/rules/*.md` | 特定ファイル編集時の制約・ガイドライン | `paths:` で対象ファイルを絞る |
| `.claude/skills/*.md` | ユーザーが明示的に呼び出す手順・ワークフロー | 手順の詳細、コード例、自動化スクリプト |

**アンチパターン**: CLAUDE.md に全部書く → 毎回全文読み込まれて肥大化し、重要な指示が埋もれる。

**推奨**: CLAUDE.md は「概要 + どのスキルを使うか」だけ記載し、詳細は rules/skills に分散させる。

---

## SKILL.md の frontmatter タイポ: `user-invokable` → `user-invocable`

### 問題

```yaml
user-invokable: true   # ❌ スペルミス
user-invocable: true   # ✅ 正しい
```

`user-invokable` という誤ったキーでは skill がユーザー呼び出し可能として登録されない可能性がある。`/skill-name` で発動させたいスキルは必ず `user-invocable` を使う。

### 確認コマンド

```bash
grep -r "user-invok" ~/.claude/skills/  # タイポを含む全スキルを検索
grep -r "user-invoc" ~/.claude/skills/  # 正しい表記を確認
```

---

## スキルの retire（廃止）判断基準

上位互換のスキルが存在する場合は古いスキルを積極的に削除する。残し続けると：
- 「どちらを使うべき？」という認知負荷が増える
- パラメータや挙動の違いで混乱する
- メンテナンスの重複コストが発生する

### 判断フロー

1. 2つのスキルで同じ目的を達成できるか？
2. 片方がもう片方の機能をすべてカバーしているか？（DPI、フォント対応、エラーハンドリングなど）
3. YES → 古い方を `rm -rf .claude/skills/<old-skill>/` で削除
4. 削除後、README.md や CLAUDE.md に残っている参照も `grep` で検索して除去する

```bash
# 旧スキルへの残存参照を検索
grep -r "convert-pptx-to-md-images" --include="*.md" .
```

---

## ローカル Git リポジトリの棚卸しコマンド集

溜まったクローン済みリポジトリを整理する際の一括調査パターン。

### 全リポジトリの最終コミット日・状態を一覧表示

```bash
for dir in ~/git/*/; do
  if [ -d "$dir/.git" ]; then
    name=$(basename "$dir")
    last_commit=$(git -C "$dir" log -1 --format='%ai' 2>/dev/null || echo "N/A")
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    echo "$last_commit | $name | branch=$branch | uncommitted=$dirty"
  fi
done | sort -r
```

### Git リポジトリでないディレクトリ（タイムスタンプ確認）

```bash
# gitなしディレクトリの最終更新ファイルを取得
find "$dir" \
  -not -path '*/node_modules/*' \
  -not -path '*/__pycache__/*' \
  -not -path '*/.venv/*' \
  -type f \
  -exec stat -f '%m %Sm' -t '%Y-%m-%d %H:%M' {} + \
  | sort -rn | head -1 | cut -d' ' -f2-
```

### 未プッシュコミットの確認

```bash
git -C "$dir" log --oneline @{upstream}..HEAD 2>/dev/null | wc -l
```

### ディスク使用量の降順確認

```bash
du -sh ~/git/*/ | sort -rh | head -20
```

---

## プッシュ可否の判断チェックリスト

削除前にプッシュが必要かどうか判断する手順：

1. **リモートの存在確認** → `git fetch origin` で `Repository not found` が出たらpush先なし
2. **外部リポジトリの直クローンか確認** → `git remote -v` で自分のアカウント名が含まれていなければforkでないのでpush不可
3. **ローカルとリモートの新旧比較** → `git fetch` 後に `git log -1 --format='%ai' origin/main` と比較。リモートが新しければローカル変更は古い
4. **未追跡ファイルの中身確認** → `git status --short` で `??` のファイルが `.claude/`・`.DS_Store` のみならゴミファイルで捨ててOK

### よくある「プッシュ不要」パターン

| 状況 | 判定 |
|---|---|
| 未追跡が `.claude/` のみ | Claude Codeの自動生成物。不要 |
| 未追跡が `.DS_Store` のみ | macOSのゴミファイル。不要 |
| READMEの一部をローカルパスに書き換えた | 自分の環境用の一時変更。不要 |
| 外部OSSリポジトリを直クローンして実験した | forkでないのでpush不可。そのまま削除 |
| `git fetch` で `Repository not found` | リモートが削除済み。push先なし |

---
