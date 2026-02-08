#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-http://127.0.0.1:8000}"
API_VERSION="${API_VERSION:-v1}"

resp="$(curl -s "$BASE_URL/$API_VERSION/chat/completions" \
  -H 'content-type: application/json' \
  -d '{
    "model":"apple-foundation-model",
    "messages":[{"role":"user","content":"What is weather in San Francisco right now?"}],
    "tools":[{
      "type":"function",
      "function":{
        "name":"get_weather",
        "description":"Get weather by city",
        "parameters":{
          "type":"object",
          "properties":{
            "city":{"type":"string"}
          },
          "required":["city"]
        }
      }
    }],
    "tool_choice":{"type":"function","function":{"name":"get_weather"}}
  }')"

if command -v jq >/dev/null 2>&1; then
  finish_reason="$(printf '%s' "$resp" | jq -r '.choices[0].finish_reason // empty')"
  tool_name="$(printf '%s' "$resp" | jq -r '.choices[0].message.tool_calls[0].function.name // empty')"

  if [[ "$finish_reason" != "tool_calls" ]]; then
    echo "FAIL: expected finish_reason=tool_calls, got: $finish_reason"
    echo "$resp"
    exit 1
  fi

  if [[ "$tool_name" != "get_weather" ]]; then
    echo "FAIL: expected tool name get_weather, got: $tool_name"
    echo "$resp"
    exit 1
  fi
else
  if [[ "$resp" != *'"finish_reason": "tool_calls"'* && "$resp" != *'"finish_reason":"tool_calls"'* ]]; then
    echo "FAIL: response did not include finish_reason=tool_calls"
    echo "$resp"
    exit 1
  fi
  if [[ "$resp" != *'"name": "get_weather"'* && "$resp" != *'"name":"get_weather"'* ]]; then
    echo "FAIL: response did not include tool name get_weather"
    echo "$resp"
    exit 1
  fi
fi

echo "PASS: function-calling is working"
