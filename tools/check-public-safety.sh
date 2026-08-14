#!/usr/bin/env bash
#
# 公開前の安全検査。設定ファイルを公開リポジトリへ出す前に、
# 「機密が混ざっていないか」と「同梱していないファイルを参照していないか」を機械で確かめる。
#
#   ./tools/check-public-safety.sh
#
# 目視は差分が増えると必ず破綻するので、公開のたびにこれを通す。
# 1件でも検出したら exit 1 で止まる。
#
# 環境固有の語（勤務先のドメイン、社内ホスト、顧客名、案件名など）は
# このスクリプトへ書かない。書いた時点で「マスク対象の一覧」という
# 別の機密になるため、gitignore した外部ファイルから読む:
#
#   tools/redaction-patterns.local.txt   … 1行1つの拡張正規表現。# 始まりはコメント
#
# tools/redaction-patterns.example.txt に書き方の例がある。

set -euo pipefail

cd "$(dirname "$0")/.."

TARGET_DIR="${1:-claude}"
LOCAL_PATTERNS="tools/redaction-patterns.local.txt"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[33m%s\033[0m\n' "$*"; }

fail_count=0

# $1=見出し, $2=拡張正規表現, $3以降=grep へ渡す追加除外パターン(任意)
scan() {
  local label="$1" pattern="$2"; shift 2
  local excludes=("$@")
  local hits
  hits=$(grep -rInE "$pattern" "$TARGET_DIR" 2>/dev/null || true)
  # bash 3.2 では空配列の "${arr[@]}" が set -u で落ちるため + で退避する
  local ex
  for ex in ${excludes[@]+"${excludes[@]}"}; do
    hits=$(printf '%s\n' "$hits" | grep -vE "$ex" || true)
  done
  hits=$(printf '%s\n' "$hits" | sed '/^$/d')
  if [ -n "$hits" ]; then
    red "NG  $label"
    printf '%s\n' "$hits" | sed 's/^/      /'
    fail_count=$((fail_count + 1))
  else
    grn "OK  $label"
  fi
}

echo "== 検査対象: $TARGET_DIR =="
echo

# ── 1. 認証情報・鍵 ──────────────────────────────────────────
scan "アクセスキー・トークン" \
  'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer [A-Za-z0-9._-]{20,}'

# ── 2. メールアドレス（noreply は許容） ──────────────────────
scan "メールアドレス実値" \
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
  'users\.noreply\.github\.com' 'example\.(com|org|net)'

# ── 3. アカウントID・電話番号 ────────────────────────────────
# 123456789012 は AWS 公式ドキュメントのダミー値なので除外する
scan "12桁のアカウントID" '\b[0-9]{12}\b' '\b123456789012\b'
scan "電話番号・郵便番号"  '0[0-9]{1,4}-[0-9]{2,4}-[0-9]{3,4}|〒[0-9]{3}-?[0-9]{4}'

# ── 4. 端末固有パス ──────────────────────────────────────────
scan "絶対ホームパス" '/Users/[a-zA-Z0-9._-]+|/home/[a-zA-Z0-9._-]+'

# ── 5. 体験談・エピソード ────────────────────────────────────
# 固有名詞（誰が・どの案件で・いつ）は本文へ溶かし、症状・原因・切り分け・対処だけ残す方針。
# 純粋な技術鮮度ラベル（「2026年時点」等）は許容するため、指摘・事故系の語だけを見る。
scan "体験談の残骸" \
  '^\s*>?\s*(由来|実績)\s*[:：]|失敗事例|（20[0-9]{2}[-年][^）]*(指摘|事故|実証|発生|体感|言われ)'

# ── 6. 環境固有パターン（ローカルファイルがあれば） ──────────
if [ -f "$LOCAL_PATTERNS" ]; then
  pat=$(grep -vE '^\s*(#|$)' "$LOCAL_PATTERNS" | paste -sd '|' -)
  if [ -n "$pat" ]; then
    scan "環境固有パターン（${LOCAL_PATTERNS}）" "$pat"
  fi
else
  ylw "--  環境固有パターン: ${LOCAL_PATTERNS} が無いのでスキップ"
  echo "      勤務先ドメイン・社内ホスト・顧客名などを1行1正規表現で置くと検査対象になる"
fi

# ── 7. 同梱していないファイルへの参照 ────────────────────────
# 参照先が無いリンクは、読者にとってのリンク切れであると同時に
# 「非公開ファイルの存在」を示唆してしまう。
dangling=""
while read -r ref; do
  [ -z "$ref" ] && continue
  [ -d "$TARGET_DIR/skills/$ref" ] || dangling+="skill: $ref"$'\n'
done < <(grep -rhoE '\bkb-[a-z0-9-]+' "$TARGET_DIR" 2>/dev/null | sort -u || true)

while read -r ref; do
  [ -z "$ref" ] && continue
  [ -f "$TARGET_DIR/$ref" ] || dangling+="rules: $ref"$'\n'
done < <(grep -rhoE 'rules/[a-z0-9-]+\.md' "$TARGET_DIR" 2>/dev/null | sort -u || true)

# バッククォート付きスラッシュ記法（`/skill-name`）のスキル参照
while read -r ref; do
  [ -z "$ref" ] && continue
  [ -d "$TARGET_DIR/skills/$ref" ] || dangling+="skill(/記法): $ref"$'\n'
done < <(grep -rhoE '`/[a-z][a-z0-9-]+`' "$TARGET_DIR" 2>/dev/null | tr -d '`/' \
           | grep -vxE 'clear|tmp|invocations|ping|health|ws' | sort -u || true)

dangling=$(printf '%s' "$dangling" | sed '/^$/d')
if [ -n "$dangling" ]; then
  red "NG  同梱していないファイルへの参照"
  printf '%s\n' "$dangling" | sed 's/^/      /'
  fail_count=$((fail_count + 1))
else
  grn "OK  同梱していないファイルへの参照"
fi

# ── 8. 中身が空の見出し ──────────────────────────────────────
# 参照や記述を削ったときに見出しだけ残りやすい。読者には壊れて見える。
# 直後に「同レベル以下（＝より浅いか同じ深さ）」の見出しが来るものだけを空とみなす。
# 見出し直後に下位見出しが続くのは正常な入れ子なので除外する。
empty_heads=$(awk '
  /^[[:space:]]*```/ { fence = !fence; next }
  fence { body = 1; next }
  match($0, /^#{1,6} /) {
    lvl = RLENGTH - 1
    if (h != "" && body == 0 && lvl <= hlvl) print f ":" hl ": " h
    h = $0; hl = FNR; hlvl = lvl; f = FILENAME; body = 0; next
  }
  /^[[:space:]]*$/ { next }
  { body = 1 }
' $(find "$TARGET_DIR" -name '*.md') 2>/dev/null || true)
if [ -n "$empty_heads" ]; then
  red "NG  中身が空の見出し"
  printf '%s\n' "$empty_heads" | sed 's/^/      /'
  fail_count=$((fail_count + 1))
else
  grn "OK  中身が空の見出し"
fi

# ── 9. コミットの author / committer ─────────────────────────
# ファイル内をいくらマスクしても、コミットのメタデータに個人メールが残る。
authors=$(git log --format='%ae%n%ce' 2>/dev/null | sort -u | grep -v 'users\.noreply\.github\.com' || true)
if [ -n "$authors" ]; then
  red "NG  コミットに noreply 以外のメールが含まれる"
  printf '%s\n' "$authors" | sed 's/^/      /'
  echo "      対処: git config user.email '<user>@users.noreply.github.com' を設定し、履歴を書き換える"
  fail_count=$((fail_count + 1))
else
  grn "OK  コミットの author / committer"
fi

echo
if [ "$fail_count" -gt 0 ]; then
  red "=== $fail_count 件の要確認あり。公開しない ==="
  exit 1
fi
grn "=== すべて合格 ==="
