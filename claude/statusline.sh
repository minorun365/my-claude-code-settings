#!/bin/bash
input=$(cat)

CONTEXT_SIZE=$(echo "$input" | jq -r '.context_window.context_window_size')
USAGE=$(echo "$input" | jq '.context_window.current_usage')

# 現在のモデル名
MODEL_RAW=$(echo "$input" | jq -r '.model.id // .model // ""' 2>/dev/null)
MODEL_LABEL=""
if echo "$MODEL_RAW" | grep -qi "opus"; then
    MODEL_LABEL="Opus"
elif echo "$MODEL_RAW" | grep -qi "sonnet"; then
    MODEL_LABEL="Sonnet"
elif echo "$MODEL_RAW" | grep -qi "haiku"; then
    MODEL_LABEL="Haiku"
fi

if [ "$USAGE" != "null" ] && [ "$CONTEXT_SIZE" != "null" ] && [ "$CONTEXT_SIZE" != "0" ]; then
    CURRENT=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    ACTUAL_PERCENT=$((CURRENT * 100 / CONTEXT_SIZE))

    # 85%を100%としてスケーリング（実際の上限が85%のため）
    SCALED_PERCENT=$((ACTUAL_PERCENT * 100 / 85))
    if [ "$SCALED_PERCENT" -gt 100 ]; then
        SCALED_PERCENT=100
    fi

    WARNING=""
    if [ "$SCALED_PERCENT" -ge 95 ]; then
        WARNING=" 🚨"
    elif [ "$SCALED_PERCENT" -ge 80 ]; then
        WARNING=" ⚠️"
    fi

    if [ -n "$MODEL_LABEL" ]; then
        echo "${MODEL_LABEL}　${SCALED_PERCENT}%${WARNING}"
    else
        echo "${SCALED_PERCENT}%${WARNING}"
    fi
else
    if [ -n "$MODEL_LABEL" ]; then
        echo "${MODEL_LABEL}　-"
    else
        echo "-"
    fi
fi
