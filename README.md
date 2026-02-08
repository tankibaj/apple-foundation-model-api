# Apple Foundation Model API

OpenAI-compatible local API server on top of Apple's Foundation Models framework.

## Why use this

- Privacy: inference runs locally on your Mac when supported.
- Zero per-request cloud API cost for local inference.
- Apple silicon optimized runtime path via Apple's stack.
- OpenAI-compatible API for easy drop-in integration.

## Requirements

- macOS with Apple Intelligence enabled.
- Apple Intelligence-compatible hardware.
- Xcode command-line tools + Swift runtime.

## Install (Global, No Clone)

Recommended distribution for users:

```bash
brew tap tankibaj/tap
brew install afm-api
```

Then run from anywhere:

```bash
afm-api
```

If command is not found:

```bash
brew link afm-api
```

## Quick Start

1. Start server (defaults: host `127.0.0.1`, port `8000`, latest API version):

```bash
afm-api
```

2. Health/API version:

```bash
curl -s http://127.0.0.1:8000/v1
```

3. List models:

```bash
curl -s http://127.0.0.1:8000/v1/models | jq
```

4. First completion:

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

## Background Mode

Start:

```bash
afm-api --background
```

Status:

```bash
afm-api --status
```

Logs:

```bash
afm-api --logs
```

Follow logs:

```bash
afm-api --logs --follow
```

Stop:

```bash
afm-api --stop
```

## Advanced

Run with custom options:

```bash
afm-api \
  --host 127.0.0.1 \
  --port 8000 \
  --api-version v1 \
  --model-name apple-foundation-model
```

- `--api-version latest` is default (currently `v1`).
- `--api-version v2` exposes `/v2/...`.

Tool-calling smoke test:

```bash
API_VERSION=v1 ./tests/test_function_call.sh http://127.0.0.1:8000
```

## Maintainers

Homebrew formula file in this repo:

- `Formula/afm-api.rb`

Before release, update formula `url` and `sha256`.

## Apple References

- [Apple Intelligence overview](https://www.apple.com/apple-intelligence/)
- [Apple Intelligence for developers](https://developer.apple.com/apple-intelligence/whats-new/)
- [Machine Learning & AI updates](https://developer.apple.com/machine-learning/whats-new/)
- [Apple Intelligence and privacy](https://support.apple.com/guide/iphone/apple-intelligence-and-privacy-iphe3f499e0e/ios)

## Notes

- `stream=true` is not implemented.
