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
require awk
require sort

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"
WARMUP="${WARMUP:-5}"
COMPLETION_N="${COMPLETION_N:-20}"
TOOL_N="${TOOL_N:-20}"
AFM_API_REQUEST_LOGS="${AFM_API_REQUEST_LOGS:-0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AFM_API_BIN="${AFM_API_BIN:-$REPO_ROOT/bin/afm-api}"

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

PARSER_HOST="$(extract_host "$BASE_URL")"
PARSER_PORT="$(extract_port "$BASE_URL")"
RUNTIME_DIR="/tmp/afm-api-perf"
STARTED_SERVER=0

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

  AFM_API_RUNTIME_DIR="$RUNTIME_DIR" AFM_API_SOURCE_ROOT="$REPO_ROOT" AFM_API_REQUEST_LOGS="$AFM_API_REQUEST_LOGS" \
    "$AFM_API_BIN" --background --host "$PARSER_HOST" --port "$PARSER_PORT" >/dev/null
  STARTED_SERVER=1

  for _ in $(seq 1 120); do
    if curl -sf "$BASE_URL/$API_VERSION/health" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done
fi

if ! curl -sf "$BASE_URL/$API_VERSION/health" >/dev/null 2>&1; then
  echo "FAIL: server not reachable at $BASE_URL"
  exit 1
fi

MODEL_ID="$(curl -s "$BASE_URL/$API_VERSION/models" | jq -r '.data[0].id // empty')"
if [[ -z "$MODEL_ID" ]]; then
  echo "FAIL: could not resolve model id from $BASE_URL/$API_VERSION/models"
  exit 1
fi

pct_ms() {
  local file="$1"
  local p="$2"
  sort -n "$file" | awk -v p="$p" '{a[NR]=$1} END { if (NR==0) { print "0.00"; exit } idx=int((NR-1)*p)+1; printf "%.2f", a[idx]*1000 }'
}

avg_ms() {
  local file="$1"
  awk '{s+=$1} END { if (NR==0) { print "0.00"; exit } printf "%.2f", (s/NR)*1000 }' "$file"
}

run_measurement() {
  local kind="$1"
  local count="$2"
  local warmup="$3"
  local times_file="$4"

  : > "$times_file"

  local payload
  if [[ "$kind" == "completion" ]]; then
    payload="$(jq -nc --arg model "$MODEL_ID" '{model:$model,messages:[{role:"user",content:"Reply with exactly OK."}],temperature:0}')"
  else
    payload="$(jq -nc --arg model "$MODEL_ID" '{model:$model,messages:[{role:"user",content:"Use get_weather for Berlin."}],tools:[{type:"function",function:{name:"get_weather",description:"Get weather",parameters:{type:"object",properties:{city:{type:"string"}},required:["city"]}}}],tool_choice:{type:"function",function:{name:"get_weather"}}}')"
  fi

  local total=$((count + warmup))
  local i
  for i in $(seq 1 "$total"); do
    local raw body t
    raw="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" -H 'content-type: application/json' -d "$payload" -w $'\n%{time_total}')"
    body="${raw%$'\n'*}"
    t="${raw##*$'\n'}"

    if [[ "$kind" == "completion" ]]; then
      local txt
      txt="$(jq -r '.choices[0].message.content // empty' <<<"$body")"
      if [[ -z "$txt" ]]; then
        echo "FAIL: completion response missing content"
        echo "$body" | jq
        exit 1
      fi
    else
      local finish tool
      finish="$(jq -r '.choices[0].finish_reason // empty' <<<"$body")"
      tool="$(jq -r '.choices[0].message.tool_calls[0].function.name // empty' <<<"$body")"
      if [[ "$finish" != "tool_calls" || -z "$tool" ]]; then
        echo "FAIL: tool-call response invalid"
        echo "$body" | jq
        exit 1
      fi
    fi

    if [[ "$i" -gt "$warmup" ]]; then
      echo "$t" >> "$times_file"
    fi
  done
}

TMP_DIR="$(mktemp -d /tmp/afm-perf.XXXXXX)"
trap 'rm -rf "$TMP_DIR"; cleanup' EXIT

COMPLETION_TIMES="$TMP_DIR/completion.times"
TOOL_TIMES="$TMP_DIR/tool.times"

run_measurement completion "$COMPLETION_N" "$WARMUP" "$COMPLETION_TIMES"
run_measurement tool "$TOOL_N" "$WARMUP" "$TOOL_TIMES"

c_avg="$(avg_ms "$COMPLETION_TIMES")"
c_p50="$(pct_ms "$COMPLETION_TIMES" 0.50)"
c_p95="$(pct_ms "$COMPLETION_TIMES" 0.95)"

t_avg="$(avg_ms "$TOOL_TIMES")"
t_p50="$(pct_ms "$TOOL_TIMES" 0.50)"
t_p95="$(pct_ms "$TOOL_TIMES" 0.95)"

echo "PASS: perf benchmark completed"
echo "PASS info: completion n=$COMPLETION_N warmup=$WARMUP avg_ms=$c_avg p50_ms=$c_p50 p95_ms=$c_p95"
echo "PASS info: tool_call n=$TOOL_N warmup=$WARMUP avg_ms=$t_avg p50_ms=$t_p50 p95_ms=$t_p95"
