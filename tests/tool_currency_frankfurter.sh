#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
require curl
require jq

first_payload='{
  "model":"apple-foundation-model",
  "messages":[{"role":"user","content":"Convert 100 USD to EUR using get_fx_rate tool."}],
  "tools":[{"type":"function","function":{"name":"get_fx_rate","description":"Convert currencies","parameters":{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"},"amount":{"type":"number"}},"required":["from","to","amount"]}}}],
  "tool_choice":{"type":"function","function":{"name":"get_fx_rate"}}
}'

first_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_payload")"
finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_resp")"
name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_resp")"
args_json="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_resp")"
if [[ "$finish" != "tool_calls" || "$name" != "get_fx_rate" ]]; then
  echo "FAIL: expected get_fx_rate tool call"
  echo "$first_resp" | jq
  exit 1
fi

from="$(jq -r '.from // "USD"' <<<"$args_json")"
to="$(jq -r '.to // "EUR"' <<<"$args_json")"
amount="$(jq -r '.amount // 100' <<<"$args_json")"

fx=$(curl -sG 'https://api.frankfurter.app/latest' \
  --data-urlencode "amount=$amount" \
  --data-urlencode "from=$from" \
  --data-urlencode "to=$to")

tool_content="$(jq -nc --arg provider "frankfurter" --argjson fx "$fx" '{provider:$provider,data:$fx}')"

second_payload="$(jq -nc \
  --arg model 'apple-foundation-model' \
  --arg args "$args_json" \
  --arg content "$tool_content" \
  '{model:$model,messages:[
      {role:"user",content:"Convert 100 USD to EUR using get_fx_rate tool."},
      {role:"assistant",content:null,tool_calls:[{id:"call_fx",type:"function",function:{name:"get_fx_rate",arguments:$args}}]},
      {role:"tool",name:"get_fx_rate",content:$content}
  ]}')"

second_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_payload")"
final_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_resp")"
if [[ -z "$final_text" ]]; then
  echo "FAIL: final response is empty"
  echo "$second_resp" | jq
  exit 1
fi

echo "PASS: currency tool flow works"
rate_value="$(jq -r --arg to "$to" '.data.rates[$to] // "n/a"' <<<"$tool_content")"
date_value="$(jq -r '.data.date // "n/a"' <<<"$tool_content")"
echo "PASS info: amount=$amount from=$from to=$to converted=$rate_value date=$date_value"
echo "PASS assistant: $final_text"
