# Architecture

`afm-api` is a small OpenAI-compatible gateway around Apple Foundation Models.

## Main Components

- `openai_api`: request/response types compatible with OpenAI-style APIs
- `capabilities`: endpoint behavior (chat completions and related logic)
- `models`: FoundationModels bridge and model-facing adapter
- `server`: HTTP server, connection handling, request processing
- `support`: logging, HTTP helpers, shared utilities

## Runtime Model

- `bin/afm-api` is a launcher.
- `afm-api-server` is the Swift server binary.
- Homebrew stable installs both as prebuilt binaries.
- Source checkout can build `afm-api-server` for local development.
