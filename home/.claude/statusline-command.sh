#!/bin/bash

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name')

input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
total=$((input_tokens + output_tokens))

tokens_display=$(awk -v t="$total" 'BEGIN {
  if (t >= 1000000) printf "%.1fm", t / 1000000;
  else if (t >= 1000) printf "%.1fk", t / 1000;
  else printf "%d", t;
}')

used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

if [ -n "$used" ]; then
  printf "%s | %s tokens (%.0f%% used)" "$model" "$tokens_display" "$used"
else
  printf "%s | %s tokens" "$model" "$tokens_display"
fi
