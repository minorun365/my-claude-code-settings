#!/bin/bash
input=$(cat)

CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')

if [ "$USAGE" != "null" ] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "0" ]; then
    CURRENT=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    ACTUAL_PERCENT=$((CURRENT * 100 / CONTEXT_SIZE))

    # 85%を100%としてスケーリング（実際の上限が85%のため）
    SCALED_PERCENT=$((ACTUAL_PERCENT * 100 / 85))
    # 100%を超えないように制限
    if [ "$SCALED_PERCENT" -gt 100 ]; then
        SCALED_PERCENT=100
    fi

    # 警告絵文字の設定（スケーリング後の値で判定）
    WARNING=""
    if [ "$SCALED_PERCENT" -ge 80 ]; then
        WARNING=" ⚠️"
    fi
    if [ "$SCALED_PERCENT" -ge 95 ]; then
        WARNING=" 🚨"
    fi

    echo "Context: ${SCALED_PERCENT}%${WARNING}"
else
    echo "Context: -"
fi
