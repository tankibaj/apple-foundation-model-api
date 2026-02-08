# Apple Foundation Model API

> Private intelligence assistant with familiar API standards

**Your Mac's intelligence. Your tools. Your data stays home.**

Use Apple's built-in intelligence without sharing anything to the cloud. Free, private and works with the tools you already know.

---

## Quick start

**Install**
```bash
brew tap tankibaj/tap
brew install afm-api
```

**Start**
```bash
afm-api
```

**Test**
```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"apple-foundation-model","messages":[{"role":"user","content":"Hello!"}]}' | jq
```

✨ **Done.** Your private OpenAI API is live at `http://127.0.0.1:8000`

---

## Why this matters

| **Completely Private** | **Totally Free** | **Easy to Use**         | **Fast & Efficient** |
|---|---|-------------------------|---|
| Everything runs on your Mac | No usage limits | Works like OpenAI API   | Optimized for Mac chips |
| Nothing sent to the internet | No monthly fees | Use with any smart tool | Runs super fast |

---

## What you need

- Mac with Apple Intelligence enabled (MacOS Tahoe 26.0 or newer)
- Apple Silicon (M1 or newer)
- Xcode command-line tools

💡 Check: System Settings → Apple Intelligence & Siri

---

## Everyday commands

```bash
afm-api                   # Start server
afm-api --background      # Run in background
afm-api --status          # Check status
afm-api --logs            # View logs
afm-api --stop            # Stop server
```

---

## Examples

**List models**
```bash
curl http://127.0.0.1:8000/v1/models | jq
```

**Chat with context**
```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "apple-foundation-model",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Explain quantum computing in one sentence."}
    ]
  }' | jq
```

**Function calling**
```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "apple-foundation-model",
    "messages": [{"role": "user", "content": "What is the weather in Tokyo?"}],
    "tools": [{
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "Get current weather",
        "parameters": {
          "type": "object",
          "properties": {"city": {"type": "string"}},
          "required": ["city"]
        }
      }
    }]
  }' | jq
```

---

## Use with your favorite tools

**Python**
```python
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:8000/v1",
    api_key="not-needed"
)

response = client.chat.completions.create(
    model="apple-foundation-model",
    messages=[{"role": "user", "content": "Hello!"}]
)
```

**Node.js**
```javascript
import OpenAI from 'openai';

const client = new OpenAI({
  baseURL: 'http://127.0.0.1:8000/v1',
  apiKey: 'not-needed'
});

const response = await client.chat.completions.create({
  model: 'apple-foundation-model',
  messages: [{ role: 'user', content: 'Hello!' }]
});
```

**LangChain**
```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    base_url="http://127.0.0.1:8000/v1",
    api_key="not-needed",
    model="apple-foundation-model"
)
```

---

## Available features

| What you can do | How to access it |
|----------|---------|
| Check if server is running | `GET /healthz` |
| See available models | `GET /v1/models` |
| Chat with intelligence | `POST /v1/chat/completions` |
| Test connection | `GET /v1/health` |

Works just like ChatGPT's interface.

---

## Troubleshooting

**Server won't start?**
```bash
# Check Apple Intelligence
# System Settings → Apple Intelligence & Siri

# Install Xcode tools
xcode-select --install
```

**Connection issues?**
```bash
afm-api --status          # Check if running
afm-api --logs            # View logs
afm-api --port 8080       # Try different port
```

**Need help?** [Open an issue](https://github.com/tankibaj/apple-foundation-model-api/issues)

---

## What you can build

- Private chat applications
- Offline smart assistants
- Zero-cost automation
- Local development tools
- Custom agents & workflows

All with libraries you already use.

---

## Advanced usage

**Custom configuration**
```bash
afm-api --host 127.0.0.1 --port 8080 --model-name custom-model
```

**Development mode**
```bash
cd /path/to/repo
./afm-api --background
./afm-api --logs --follow
```

**Run tests**
```bash
./tests/test_function_call.sh
```
**Function Calling Examples (real APIs)**
```bash
# Country info
./tests/test_tool_country_info_restcountries.sh http://127.0.0.1:8000

# Currency conversion
./tests/test_tool_currency_frankfurter.sh http://127.0.0.1:8000

# Public holidays
./tests/test_tool_public_holidays_nager.sh http://127.0.0.1:8000

# Time zone
./tests/test_tool_timezone_worldtimeapi.sh http://127.0.0.1:8000

# Weather
./tests/test_tool_weather_openmeteo.sh http://127.0.0.1:8000
```

**Update**
```bash
brew update
brew upgrade afm-api
```

**Automated Homebrew updates (maintainers)**
```bash
# Required once in apple-foundation-model-api repo settings:
# secret: HOMEBREW_TAP_TOKEN (PAT with write access to tankibaj/homebrew-tap)
#
# Then every GitHub Release (vX.Y.Z) auto-updates:
# - Formula/afm-api.rb
# - Formula/afm-api@X.Y.rb
```

---
## What's coming soon

- Live-streaming responses (currently you get the full response at once)
- Support for more Apple Intelligence models
- Works only on newer Macs with Apple Intelligence right now

---

## Learn more

- [Apple Intelligence](https://developer.apple.com/documentation/foundationmodels)
- [Apple Intelligence Privacy](https://www.apple.com/legal/privacy/data/en/intelligence-engine/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference/chat)

---

## Contributing

We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

---

**Questions or feedback?** We'd love to hear from you.

Built with ❤️ for the Apple Silicon community
