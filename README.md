# Apple Foundation Model API

> Private intelligence assistant with familiar API standards

**Your Mac's intelligence. Your tools. Your data stays home.**

Use Apple's built-in intelligence without sending prompts to cloud LLM providers. `afm-api` exposes local Apple Foundation Models with OpenAI-compatible endpoints.

---

## Quick Start

Install:

```bash
brew tap tankibaj/tap
brew install afm-api
```

Start server:

```bash
afm-api
```

First completion:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"apple-foundation-model","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

Function-calling smoke test:

```bash
./tests/function_call.sh
```

Your local API is now live at `http://127.0.0.1:8000`.

---

## Requirements

- macOS 26.0+ with Apple Intelligence enabled
- Apple Silicon (M1 or newer)
- Xcode command-line tools

Check Apple Intelligence in System Settings:
`Apple Intelligence & Siri`

---

## Everyday Commands

```bash
afm-api                   # Start server
afm-api --background      # Run in background
afm-api --status          # Check status
afm-api --logs            # Show logs
afm-api --stop            # Stop server
afm-api --version         # Show installed version
```

---

## Core Endpoints

- `GET /v1/health`
- `GET /v1/models`
- `POST /v1/chat/completions`

---

## Update

```bash
brew update
brew upgrade afm-api
```

---

## Documentation

- [Development Guide](./docs/development.md)
- [Testing Guide](./docs/testing.md)
- [Homebrew Guide](./docs/homebrew.md)
- [Local Homebrew Feature-Branch Testing](./docs/homebrew-local-testing.md)
- [Stable Release Process (Prebuilt Binary)](./docs/release.md)
- [Architecture](./docs/architecture.md)

---

## References

- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels)
- [Apple Intelligence Privacy](https://www.apple.com/legal/privacy/data/en/intelligence-engine/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference/chat)
