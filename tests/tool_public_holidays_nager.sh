#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
require curl
require jq

first_payload='{
  "model":"apple-foundation-model",
  "messages":[{"role":"user","content":"Get public holidays for Berlin in 2026 using get_public_holidays tool."}],
  "tools":[{"type":"function","function":{"name":"get_public_holidays","description":"Get public holidays by city and year","parameters":{"type":"object","properties":{"city":{"type":"string"},"year":{"type":"integer"}},"required":["city","year"]}}}],
  "tool_choice":{"type":"function","function":{"name":"get_public_holidays"}}
}'

first_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_payload")"
finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_resp")"
name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_resp")"
args_json="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_resp")"
if [[ "$finish" != "tool_calls" || "$name" != "get_public_holidays" ]]; then
  echo "FAIL: expected get_public_holidays tool call"
  echo "$first_resp" | jq
  exit 1
fi

city="$(jq -r '.city // "Berlin"' <<<"$args_json")"
year="$(jq -r '.year // 2026' <<<"$args_json")"

geo=$(curl -sG 'https://geocoding-api.open-meteo.com/v1/search' --data-urlencode "name=$city" --data-urlencode 'count=1')
country_code="$(jq -r '.results[0].country_code // empty' <<<"$geo")"
if [[ -z "$country_code" ]]; then
  echo "FAIL: could not map city to country code"
  echo "$geo" | jq
  exit 1
fi

holidays="$(curl -s "https://date.nager.at/api/v3/PublicHolidays/$year/$country_code")"
tool_content="$(jq -nc --arg city "$city" --arg cc "$country_code" --arg year "$year" --argjson holidays "$holidays" '{city:$city,country_code:$cc,year:$year,holidays:$holidays}')"

second_payload="$(jq -nc \
  --arg model 'apple-foundation-model' \
  --arg args "$args_json" \
  --arg content "$tool_content" \
  '{model:$model,messages:[
      {role:"user",content:"Get public holidays for Berlin in 2026 using get_public_holidays tool."},
      {role:"assistant",content:null,tool_calls:[{id:"call_holidays",type:"function",function:{name:"get_public_holidays",arguments:$args}}]},
      {role:"tool",name:"get_public_holidays",content:$content}
  ]}')"

second_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_payload")"
final_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_resp")"
if [[ -z "$final_text" ]]; then
  echo "FAIL: final response is empty"
  echo "$second_resp" | jq
  exit 1
fi

echo "PASS: public holidays tool flow works"
holiday_count="$(jq -r '.holidays | length' <<<"$tool_content")"
first_holiday="$(jq -r '.holidays[0].localName // "n/a"' <<<"$tool_content")"
echo "PASS info: city=$city country_code=$country_code year=$year holidays=$holiday_count first=$first_holiday"
echo "PASS assistant: $final_text"
