#!/bin/bash
input=$(cat)

CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')

if [ "$USAGE" != "null" ] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "0" ]; then
    CURRENT=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    PERCENT=$((CURRENT * 100 / CONTEXT_SIZE))

    # 警告絵文字の設定
    WARNING=""
    if [ "$PERCENT" -ge 50 ]; then
        WARNING=" ⚠️"
    fi
    if [ "$PERCENT" -ge 70 ]; then
        WARNING=" 🚨"
    fi

    echo "Context: ${PERCENT}%${WARNING}"
else
    echo "Context: -"
fi
