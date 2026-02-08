#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }
require curl
require jq

first_payload='{
  "model":"apple-foundation-model",
  "messages":[{"role":"user","content":"Get current weather for Berlin using the get_weather tool."}],
  "tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather for a city","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}],
  "tool_choice":{"type":"function","function":{"name":"get_weather"}}
}'

first_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_payload")"

finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_resp")"
name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_resp")"
args_json="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_resp")"
if [[ "$finish" != "tool_calls" || "$name" != "get_weather" ]]; then
  echo "FAIL: expected get_weather tool call"
  echo "$first_resp" | jq
  exit 1
fi

city="$(jq -r '.city // "Berlin"' <<<"$args_json")"

g=$(curl -sG 'https://geocoding-api.open-meteo.com/v1/search' --data-urlencode "name=$city" --data-urlencode 'count=1')
lat="$(jq -r '.results[0].latitude // empty' <<<"$g")"
lon="$(jq -r '.results[0].longitude // empty' <<<"$g")"
if [[ -z "$lat" || -z "$lon" ]]; then
  echo "FAIL: geocoding failed for city=$city"
  echo "$g" | jq
  exit 1
fi

w=$(curl -sG 'https://api.open-meteo.com/v1/forecast' \
  --data-urlencode "latitude=$lat" \
  --data-urlencode "longitude=$lon" \
  --data-urlencode 'current=temperature_2m,weather_code')

tool_content="$(jq -nc --arg city "$city" --arg provider "open-meteo" --argjson weather "$w" '{city:$city,provider:$provider,current:$weather.current}')"

second_payload="$(jq -nc \
  --arg model 'apple-foundation-model' \
  --arg city "$city" \
  --arg args "$args_json" \
  --arg content "$tool_content" \
  '{model:$model,messages:[
      {role:"user",content:("Get current weather for " + $city + " using the get_weather tool.")},
      {role:"assistant",content:null,tool_calls:[{id:"call_weather",type:"function",function:{name:"get_weather",arguments:$args}}]},
      {role:"tool",name:"get_weather",content:$content}
  ]}')"

second_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_payload")"
final_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_resp")"
if [[ -z "$final_text" ]]; then
  echo "FAIL: final response is empty"
  echo "$second_resp" | jq
  exit 1
fi

echo "PASS: weather tool flow works"
temperature="$(jq -r '.current.temperature_2m // "n/a"' <<<"$tool_content")"
weather_code="$(jq -r '.current.weather_code // "n/a"' <<<"$tool_content")"
echo "PASS info: city=$city temperature_2m=$temperature weather_code=$weather_code"
echo "PASS assistant: $final_text"
