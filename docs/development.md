# Development Guide

## Local Run

```bash
# From repo root
./bin/afm-api --host 127.0.0.1 --port 8000 --api-version latest
```

Background mode:

```bash
./bin/afm-api --background
./bin/afm-api --status
./bin/afm-api --logs --follow
./bin/afm-api --stop
```

## Build

Build server binary from source:

```bash
./bin/afm-api build
```

Force clean rebuild:

```bash
./bin/afm-api --rebuild
```

## Runtime Safety Knobs

Force prebuilt-only runtime (no local Swift build fallback):

```bash
AFM_API_REQUIRE_PREBUILT=1 afm-api --background
```

Tune launcher wait windows:

```bash
AFM_API_STARTUP_TIMEOUT_SEC=30 AFM_API_SHUTDOWN_TIMEOUT_SEC=15 afm-api --background
```

## Tests

Core function call test:

```bash
./tests/function_call.sh
```

Real API tool-call examples:

```bash
./tests/tool_country_info_restcountries.sh http://127.0.0.1:8000
./tests/tool_currency_frankfurter.sh http://127.0.0.1:8000
./tests/tool_public_holidays_nager.sh http://127.0.0.1:8000
./tests/tool_timezone_worldtimeapi.sh http://127.0.0.1:8000
./tests/tool_weather_openmeteo.sh http://127.0.0.1:8000
```

## Project Layout

```text
Package.swift
Sources/AFMAPI/openai_api
Sources/AFMAPI/capabilities
Sources/AFMAPI/models
Sources/AFMAPI/support
Sources/AFMAPI/server
```
