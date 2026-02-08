#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
require curl
require jq

first_payload='{
  "model":"apple-foundation-model",
  "messages":[{"role":"user","content":"Get current time in Europe/Berlin using get_time tool."}],
  "tools":[{"type":"function","function":{"name":"get_time","description":"Get current time by timezone","parameters":{"type":"object","properties":{"timezone":{"type":"string"}},"required":["timezone"]}}}],
  "tool_choice":{"type":"function","function":{"name":"get_time"}}
}'

first_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_payload")"
finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_resp")"
name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_resp")"
args_json="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_resp")"
if [[ "$finish" != "tool_calls" || "$name" != "get_time" ]]; then
  echo "FAIL: expected get_time tool call"
  echo "$first_resp" | jq
  exit 1
fi

timezone="$(jq -r '.timezone // "Europe/Berlin"' <<<"$args_json")"
city="$(awk -F/ '{print $NF}' <<<"$timezone")"
geo="$(curl -sG 'https://geocoding-api.open-meteo.com/v1/search' --data-urlencode "name=$city" --data-urlencode 'count=1')"
lat="$(jq -r '.results[0].latitude // empty' <<<"$geo")"
lon="$(jq -r '.results[0].longitude // empty' <<<"$geo")"
if [[ -z "$lat" || -z "$lon" ]]; then
  echo "FAIL: geocoding failed for timezone/city=$timezone/$city"
  echo "$geo" | jq
  exit 1
fi
time_resp="$(curl -sG 'https://api.open-meteo.com/v1/forecast' \
  --data-urlencode "latitude=$lat" \
  --data-urlencode "longitude=$lon" \
  --data-urlencode "timezone=$timezone" \
  --data-urlencode 'current=temperature_2m')"

tool_content="$(jq -nc --arg timezone "$timezone" --arg provider "open-meteo" --argjson data "$time_resp" '{timezone:$timezone,provider:$provider,data:$data.current}')"

second_payload="$(jq -nc \
  --arg model 'apple-foundation-model' \
  --arg args "$args_json" \
  --arg content "$tool_content" \
  '{model:$model,messages:[
      {role:"user",content:"Get current time in Europe/Berlin using get_time tool."},
      {role:"assistant",content:null,tool_calls:[{id:"call_time",type:"function",function:{name:"get_time",arguments:$args}}]},
      {role:"tool",name:"get_time",content:$content}
  ]}')"

second_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_payload")"
final_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_resp")"
if [[ -z "$final_text" ]]; then
  echo "FAIL: final response is empty"
  echo "$second_resp" | jq
  exit 1
fi

echo "PASS: timezone tool flow works"
temp_now="$(jq -r '.data.temperature_2m // "n/a"' <<<"$tool_content")"
echo "PASS info: timezone=$timezone city=$city temperature_2m=$temp_now"
echo "PASS assistant: $final_text"
