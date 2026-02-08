# Apple Foundation Model OpenAI-Compatible Server

Headless CLI server that exposes Apple Foundation Model via OpenAI-compatible endpoints.

## What it provides

- `GET /v1/models`
- `POST /v1/chat/completions`
- OpenAI-style request/response payloads
- Tool calling support (`tools`, `tool_choice`) compatible with OpenAI chat-completions semantics

## Requirements

- macOS with Apple Intelligence enabled
- Xcode toolchain with Swift Concurrency support
- Access to Apple's `FoundationModels` framework on your OS/Xcode version

## Quick start

Run native Swift server directly:

```bash
./bin/afm-api --host 127.0.0.1 --port 8000 --api-version v1
```

## Homebrew Formula

A formula template is included at:

- `Formula/afm-api.rb`

Before publishing, update:

- `url` tag version (for example `v0.1.0`)
- `sha256` with the real release tarball checksum

This exposes the same endpoints:
- `GET /healthz`
- `GET /v1`
- `GET /v1/models`
- `POST /v1/chat/completions`

Change API namespace with `--api-version` (for example `--api-version v2` exposes `/v2/...`).

## Example

```bash
curl -s http://127.0.0.1:8000/v1/models | jq
```

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "apple-foundation-model",
    "messages": [
      {"role":"system","content":"You are concise."},
      {"role":"user","content":"Say hello in one sentence."}
    ]
  }' | jq
```

### Tool calling example

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "apple-foundation-model",
    "messages": [
      {"role":"user","content":"What is the weather in SF?"}
    ],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get weather",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          },
          "required": ["city"]
        }
      }
    }]
  }' | jq
```

If the model decides to call a tool, response includes `choices[0].message.tool_calls` with JSON arguments.

## Test function calling

In a second terminal (while server is running):

```bash
./tests/test_function_call.sh http://127.0.0.1:8000
```

Expected output:

```text
PASS: function-calling is working
```

## Notes

- Streaming (`stream=true`) is currently not implemented.
- Tool call generation is done with a strict JSON contract prompt so it works even when native function-calling APIs vary by OS release.
