# Testing Guide

## Quick Smoke Test

```bash
afm-api --background
curl -s http://127.0.0.1:8000/v1/health | jq
afm-api --stop
```

## Chat Completion

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "apple-foundation-model",
    "messages": [{"role":"user","content":"Say hello."}]
  }' | jq
```

## Function Calling

```bash
./tests/function_call.sh
```

## Real API Tool Tests

```bash
./tests/tool_country_info_restcountries.sh http://127.0.0.1:8000
./tests/tool_currency_frankfurter.sh http://127.0.0.1:8000
./tests/tool_public_holidays_nager.sh http://127.0.0.1:8000
./tests/tool_timezone_worldtimeapi.sh http://127.0.0.1:8000
./tests/tool_weather_openmeteo.sh http://127.0.0.1:8000
```

## Performance

```bash
./tests/perf_chat_and_tools.sh http://127.0.0.1:8000
```
