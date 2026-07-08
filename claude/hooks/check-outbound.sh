#!/bin/bash
# PreToolUse hook: 外部書き込みコマンドの検出
#
# gh CLI の書き込み系コマンドを検出し、宛先リポジトリの owner を抽出して判定する。
# - 自分のリポジトリ（OWN_OWNERS）への操作 → そのまま通過
# - 他者のリポジトリ、または宛先を特定できない場合 → permissionDecision=ask で
#   許可ダイアログに切り替える（settings.json の Bash(*) 自動許可より優先される）
#
# 宛先は「コマンド文字列に owner 名が含まれるか」ではなく、
# -R/--repo フラグ・GitHub URL・API パス（repos/<owner>/...）から抽出して厳密比較する。

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Bash ツール以外は通過
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [ -z "$command" ]; then
  exit 0
fi

# 自分のアカウント（スペース区切りで複数指定可）
OWN_OWNERS="minorun365"

# permissionDecision=ask を返して許可ダイアログに切り替える
ask() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# --- gh の書き込み系コマンドか判定 ---

is_gh_write=false

if echo "$command" | grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|review|close|reopen|edit|merge|transfer|delete|lock)'; then
  is_gh_write=true
elif echo "$command" | grep -qE 'gh[[:space:]]+(release|gist)[[:space:]]+(create|edit|delete|upload)'; then
  is_gh_write=true
elif echo "$command" | grep -qE 'gh[[:space:]]+repo[[:space:]]+(delete|edit|rename|archive)'; then
  is_gh_write=true
elif echo "$command" | grep -qE 'gh[[:space:]]+api[[:space:]]'; then
  # gh api 以降の部分だけを検査（rm -f 等、無関係なフラグの誤検出を避ける）
  api_seg=$(echo "$command" | sed -E 's/.*gh[[:space:]]+api[[:space:]]//')
  # 明示的な書き込みメソッド、またはフィールド指定（暗黙で POST になる）を検出
  if echo "$command" | grep -qE '(-X|--method)[= ][[:space:]]*(POST|PUT|PATCH|DELETE)'; then
    is_gh_write=true
  elif echo " $api_seg" | grep -qE '[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]=]'; then
    is_gh_write=true
  fi
fi

if [ "$is_gh_write" != "true" ]; then
  exit 0
fi

# --- 宛先リポジトリの owner を抽出 ---

# 1. -R / --repo フラグ
target=$(echo "$command" | grep -oE '(-R|--repo)[= ][[:space:]]*[^[:space:]]+' | head -1 | sed -E 's/^(-R|--repo)[= ][[:space:]]*//')
# 2. GitHub URL（GHE 等のホストも対象にするため github.* で判定）
if [ -z "$target" ]; then
  target=$(echo "$command" | grep -oE 'github\.[^/[:space:]]+/[^[:space:]"'\'']+' | head -1 | sed -E 's|^github\.[^/]+/||')
fi
# 3. gh api の repos/<owner>/... パス
if [ -z "$target" ]; then
  target=$(echo "$command" | grep -oE 'repos/[^/[:space:]"'\'']+/' | head -1 | sed 's|^repos/||')
fi
# 4. positional 引数の owner/repo（gh repo delete minorun365/foo 等）
#    gh コマンド以降の文字列だけを対象に抽出する（cd のパス等の誤検出を避ける）
if [ -z "$target" ]; then
  gh_seg=$(echo "$command" | grep -oE 'gh[[:space:]].*' | head -1)
  target=$(echo "$gh_seg" | grep -oE '(^|[[:space:]])[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' | head -1 | sed 's/^[[:space:]]*//')
fi

owner=$(echo "$target" | sed -E 's|^https?://[^/]+/||' | cut -d/ -f1 | tr -d '/')

# 自分のリポジトリへの操作だけ通過。他者宛て・宛先不明は許可ダイアログへ
for own in $OWN_OWNERS; do
  if [ "$owner" = "$own" ]; then
    exit 0
  fi
done

ask "外部リポジトリへの書き込みの可能性があります（宛先: ${owner:-不明}）。宛先と内容を確認してください。"
