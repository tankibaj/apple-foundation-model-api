#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
require curl
require jq

first_payload='{
  "model":"apple-foundation-model",
  "messages":[{"role":"user","content":"Get country information for Germany using get_country_info tool."}],
  "tools":[{"type":"function","function":{"name":"get_country_info","description":"Get country information","parameters":{"type":"object","properties":{"country":{"type":"string"}},"required":["country"]}}}],
  "tool_choice":{"type":"function","function":{"name":"get_country_info"}}
}'

first_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_payload")"
finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_resp")"
name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_resp")"
args_json="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_resp")"
if [[ "$finish" != "tool_calls" || "$name" != "get_country_info" ]]; then
  echo "FAIL: expected get_country_info tool call"
  echo "$first_resp" | jq
  exit 1
fi

country="$(jq -r '.country // "Germany"' <<<"$args_json")"
country_data="$(curl -s --max-time 20 "https://restcountries.com/v3.1/name/$country?fullText=true")"
country_summary="$(jq -c '.[0] | {
  name: .name.common,
  official_name: .name.official,
  capital: (.capital[0] // null),
  region: .region,
  subregion: .subregion,
  population: .population,
  currencies: (.currencies | keys)
}' <<<"$country_data")"
tool_content="$(jq -nc --arg country "$country" --argjson summary "$country_summary" '{country:$country,data:$summary}')"

second_payload="$(jq -nc \
  --arg model 'apple-foundation-model' \
  --arg args "$args_json" \
  --arg content "$tool_content" \
  '{model:$model,messages:[
      {role:"user",content:"Get country information for Germany using get_country_info tool."},
      {role:"assistant",content:null,tool_calls:[{id:"call_country",type:"function",function:{name:"get_country_info",arguments:$args}}]},
      {role:"tool",name:"get_country_info",content:$content}
  ]}')"

second_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_payload")"
final_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_resp")"
if [[ -z "$final_text" ]]; then
  echo "FAIL: final response is empty"
  echo "$second_resp" | jq
  exit 1
fi

capital="$(jq -r '.capital // "n/a"' <<<"$country_summary")"
population="$(jq -r '.population // "n/a"' <<<"$country_summary")"
region="$(jq -r '.region // "n/a"' <<<"$country_summary")"
echo "PASS: country info tool flow works"
echo "PASS info: country=$country capital=$capital region=$region population=$population"
echo "PASS assistant: $final_text"
