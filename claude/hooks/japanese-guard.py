#!/usr/bin/env python3
"""Claude Code の Stop hook。ターンの本文が英語主体なら、終了させずに日本語で書き直させる。

検査するのは、そのターンの最終回答だけ。つまり最後のツール呼び出しより後に Claude が書いた本文。
ツールを呼ぶ前の途中の一言は、画面では実行ログの間に小さく出るだけなので対象にしない。
ツールを1回も呼ばなかったターンは、本文すべてが最終回答になる。
最終回答は hook の入力 last_assistant_message でも見る。transcript への書き込みが遅れても
見逃さないため。入るのは最後の応答1件だけなので、transcript の判定も残して両方で見る。
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
import time

# 英字がこれ未満の本文は判定しない（「OK」「Done」程度の短い返事は見逃す）
MIN_LATIN = int(os.environ.get("JAPANESE_GUARD_MIN_LATIN", "25"))
# 英字の数が日本語の文字数のこの倍を超えたら、英語主体とみなす
RATIO = float(os.environ.get("JAPANESE_GUARD_RATIO", "3"))
# 最終回答が transcript へ書き込まれるのを待つ上限（秒）
WAIT_SECONDS = float(os.environ.get("JAPANESE_GUARD_WAIT", "3"))

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
    "ユーザーは日本語での応答を求めています。上に挙げた英語の箇所だけを、日本語に書き直して出してください。"
    "日本語で書けていた部分は、すでにユーザーに届いているので再掲しないこと。"
    "言い訳や原因の説明は書かず、以降の応答もすべて日本語で書くこと。"
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


def read_entries(transcript_path):
    entries = []
    with open(transcript_path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            try:
                entries.append(json.loads(line))
            except ValueError:
                continue
    return entries


def turn_ended_in_text(entries):
    """このターンの最新の assistant エントリが、本文で終わっているか"""
    for entry in reversed(entries):
        if is_user_turn(entry):
            return False
        if entry.get("type") == "assistant":
            content = entry.get("message", {}).get("content") or []
            last = next((c for c in reversed(content) if isinstance(c, dict)), None)
            return bool(last) and last.get("type") == "text"
        if entry.get("type") == "user":  # ツール結果が最後＝最終回答がまだ書き込まれていない
            return False
    return False


def wait_for_final(transcript_path, timeout=WAIT_SECONDS):
    """Stop hook は、最終回答が transcript へ書き込まれる前に呼ばれることがある。
    そのまま読むと最終回答が見えず、英語でも素通りする。最終回答が現れるまで待つ。
    ツールを呼ばずに終わったターンは最初から本文で終わっているので、待たずに進む。"""
    deadline = time.time() + timeout
    entries = read_entries(transcript_path)
    while not turn_ended_in_text(entries) and time.time() < deadline:
        time.sleep(0.1)
        entries = read_entries(transcript_path)
    return entries


def english_passages(transcript_path, entries=None):
    if entries is None:
        entries = read_entries(transcript_path)
    start = 0
    for i, entry in enumerate(entries):
        if is_user_turn(entry):
            start = i + 1
    # 最終回答＝最後のツール呼び出しより後の本文。ツール呼び出しが出るたびに集め直す
    final = []
    for entry in entries[start:]:
        if entry.get("type") != "assistant":
            continue
        for block in entry.get("message", {}).get("content") or []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use":
                final = []
            elif block.get("type") == "text":
                final.append(block.get("text", ""))
    hits = [text.strip().splitlines()[0][:80] for text in final if is_english(text)]
    return hits


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        hits = english_passages(sys.argv[2])
        print("\n".join(hits) if hits else "英語主体の本文はありません")
        return
    data = json.load(sys.stdin)
    if data.get("stop_hook_active"):
        return
    # 最終回答の本文は hook の入力 last_assistant_message にも入っている。transcript の書き込みを
    # 待たずに判定でき、書き込みが遅れても見逃さない。入るのは最後の応答1件だけなので、
    # 応答が分かれたときの前半は transcript 側で見る（issue #1）
    message = data.get("last_assistant_message") or ""
    message_en = bool(message) and is_english(message)
    path = data.get("transcript_path")
    hits = []
    if path:
        try:
            hits = english_passages(path, read_entries(path) if message_en else wait_for_final(path))
        except OSError:
            pass
    if message_en:
        head = message.strip().splitlines()[0][:80]
        if head not in hits:
            hits.append(head)
    if hits:
        quoted = "\n".join("- " + h for h in hits[:5])
        print(json.dumps({"decision": "block", "reason": REASON.format(quoted=quoted)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
