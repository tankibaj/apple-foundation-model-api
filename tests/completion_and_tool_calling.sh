#!/usr/bin/env bash
set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FAIL: missing command: $1"
    exit 1
  }
}

require curl
require jq

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AFM_API_BIN="${AFM_API_BIN:-$REPO_ROOT/bin/afm-api}"
RUNTIME_DIR="/tmp/afm-api-smoke"
STARTED_SERVER=0

extract_host() {
  echo "$1" | sed -E 's#^https?://([^:/]+).*$#\1#'
}

extract_port() {
  local p
  p="$(echo "$1" | sed -nE 's#^https?://[^:/]+:([0-9]+).*$#\1#p')"
  if [[ -n "$p" ]]; then
    echo "$p"
  else
    echo "8000"
  fi
}

cleanup() {
  if [[ "$STARTED_SERVER" == "1" ]]; then
    AFM_API_RUNTIME_DIR="$RUNTIME_DIR" "$AFM_API_BIN" --stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! curl -sf "$BASE_URL/$API_VERSION/health" >/dev/null 2>&1; then
  if [[ ! -x "$AFM_API_BIN" ]]; then
    echo "FAIL: server is not reachable at $BASE_URL and no local afm-api launcher found at $AFM_API_BIN"
    exit 1
  fi

  HOST="$(extract_host "$BASE_URL")"
  PORT="$(extract_port "$BASE_URL")"
  AFM_API_RUNTIME_DIR="$RUNTIME_DIR" AFM_API_SOURCE_ROOT="$REPO_ROOT" "$AFM_API_BIN" --background --host "$HOST" --port "$PORT" >/dev/null
  STARTED_SERVER=1

  for _ in $(seq 1 120); do
    if curl -sf "$BASE_URL/$API_VERSION/health" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

MODEL_ID="$(curl -s "$BASE_URL/$API_VERSION/models" | jq -r '.data[0].id // empty')"
if [[ -z "$MODEL_ID" ]]; then
  echo "FAIL: could not resolve model id from $BASE_URL/$API_VERSION/models"
  exit 1
fi

completion_payload="$(jq -nc --arg model "$MODEL_ID" '{model:$model,messages:[{role:"user",content:"Reply with one word: hello"}],temperature:0}')"
completion_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$completion_payload")"
completion_text="$(jq -r '.choices[0].message.content // empty' <<<"$completion_resp")"
if [[ -z "$completion_text" ]]; then
  echo "FAIL: completion returned empty text"
  echo "$completion_resp" | jq
  exit 1
fi

first_tool_payload="$(jq -nc --arg model "$MODEL_ID" '{model:$model,messages:[{role:"user",content:"Use get_weather for Berlin."}],tools:[{type:"function",function:{name:"get_weather",description:"Get weather by city",parameters:{type:"object",properties:{city:{type:"string"}},required:["city"]}}}],tool_choice:{type:"function",function:{name:"get_weather"}}}')"
first_tool_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$first_tool_payload")"

finish_reason="$(jq -r '.choices[0].finish_reason // empty' <<<"$first_tool_resp")"
tool_name="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$first_tool_resp")"
tool_args="$(jq -r '.choices[0].message.tool_calls[0].function.arguments // "{}"' <<<"$first_tool_resp")"

if [[ "$finish_reason" != "tool_calls" || "$tool_name" != "get_weather" ]]; then
  echo "FAIL: expected tool call to get_weather"
  echo "$first_tool_resp" | jq
  exit 1
fi

mock_tool_result='{"city":"Berlin","temperature_c":8,"condition":"Cloudy"}'
second_tool_payload="$(jq -nc \
  --arg model "$MODEL_ID" \
  --arg args "$tool_args" \
  --arg toolContent "$mock_tool_result" \
  '{model:$model,messages:[
      {role:"user",content:"Use get_weather for Berlin."},
      {role:"assistant",content:null,tool_calls:[{id:"call_1",type:"function",function:{name:"get_weather",arguments:$args}}]},
      {role:"tool",name:"get_weather",content:$toolContent}
  ]}')"

second_tool_resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$second_tool_payload")"
second_text="$(jq -r '.choices[0].message.content // empty' <<<"$second_tool_resp")"

if [[ -z "$second_text" ]]; then
  echo "FAIL: final response after tool result is empty"
  echo "$second_tool_resp" | jq
  exit 1
fi

echo "PASS: completion and tool-calling flow works"
echo "PASS info: completion_text=$completion_text"
echo "PASS info: tool_name=$tool_name tool_args=$tool_args"
echo "PASS assistant: $second_text"
