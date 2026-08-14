#!/usr/bin/env python3
"""Claude Code の Stop hook。ターンの本文が英語主体なら、終了させずに日本語で書き直させる。

検査するのは「最後のユーザー発言より後に Claude が書いた本文すべて」（途中の一言報告も含む）。
コードブロック・インラインコード・URL・メールアドレス・Markdown リンクは数えない。
英語のコマンドや英文の下書きをコードブロックで見せるのは正当なため。

差し戻しは1ターンにつき1回だけ（stop_hook_active が立っていたら通す）。
書き直しが再び英語になっても、そこで止めて無限に続かないようにする。

単体で試す: python3 japanese-guard.py --check <transcript.jsonl>
"""

import json
import os
import re
import sys

# 英字がこれ未満の本文は判定しない（「OK」「Done」程度の短い返事は見逃す）
MIN_LATIN = int(os.environ.get("JAPANESE_GUARD_MIN_LATIN", "25"))
# 英字の数が日本語の文字数のこの倍を超えたら、英語主体とみなす
RATIO = float(os.environ.get("JAPANESE_GUARD_RATIO", "3"))

JA = re.compile(r"[ぁ-んァ-ヶ一-龥]")
LATIN = re.compile(r"[A-Za-z]")
IGNORE = [
    re.compile(r"```.*?```", re.S),
    re.compile(r"`[^`\n]*`"),
    re.compile(r"https?://\S+"),
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+"),
    re.compile(r"\[[^\]]*\]\([^)]*\)"),
]

REASON = (
    "このターンの本文に、英語で書いた箇所があります。\n"
    "{quoted}\n"
    "ユーザーは日本語での応答を求めています。このターンで英語で書いた内容（途中の一言報告を含む）を、"
    "日本語で全部書き直して出し直してください。言い訳や原因の説明は書かず、書き直した本文だけを出すこと。"
    "以降の応答もすべて日本語で書くこと。"
)


def is_english(text):
    for pattern in IGNORE:
        text = pattern.sub("", text)
    latin = len(LATIN.findall(text))
    ja = len(JA.findall(text))
    return latin >= MIN_LATIN and latin > ja * RATIO


def is_user_turn(entry):
    """ユーザーが入力した発言か（ツール結果やメタ情報の user エントリを除く）"""
    if entry.get("type") != "user" or entry.get("isMeta"):
        return False
    content = entry.get("message", {}).get("content")
    if isinstance(content, str):
        return True
    if isinstance(content, list):
        return not any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False


def english_passages(transcript_path):
    entries = []
    with open(transcript_path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue
    start = 0
    for i, entry in enumerate(entries):
        if is_user_turn(entry):
            start = i + 1
    hits = []
    for entry in entries[start:]:
        if entry.get("type") != "assistant":
            continue
        for block in entry.get("message", {}).get("content") or []:
            if isinstance(block, dict) and block.get("type") == "text" and is_english(block.get("text", "")):
                hits.append(block["text"].strip().splitlines()[0][:80])
    return hits


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        hits = english_passages(sys.argv[2])
        print("\n".join(hits) if hits else "英語主体の本文はありません")
        return
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return
    path = data.get("transcript_path")
    if not path:
        return
    try:
        hits = english_passages(path)
    except OSError:
        return
    if hits:
        quoted = "\n".join("- " + h for h in hits[:5])
        print(json.dumps({"decision": "block", "reason": REASON.format(quoted=quoted)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
