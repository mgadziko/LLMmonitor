# LLMmonitor

A native macOS app for keeping a local library of machines that serve large language models.

LLMmonitor shows an at-a-glance table of each remembered machine: online state, server type, endpoint, installed models, and last-seen time. Machines stay in the library—and keep their last-known model inventory—even when they are offline.

## Discovery and polling

- **Ollama**: `GET /api/tags` (default port `11434`)
- **OpenAI-compatible servers**: `GET /v1/models`
- **LM Studio**: `GET /api/v0/models`

Use **Scan LAN** to probe the active IPv4 `/24` network on ports 11434, 11435, 1234, and 8080. For nonstandard networks, VPNs, and hosts with authentication, add machines manually. The app deliberately makes only read-only HTTP GET requests and sends no credentials.

## Build and run

```sh
./Scripts/build-app.sh
open LLMmonitor.app
```

This creates `LLMmonitor.app`, a standard application bundle with a Dock icon. Open the package in Xcode for normal macOS development. The package targets macOS 14 or later.

## Data

The local library is saved at `~/Library/Application Support/LLMmonitor/machines.json`.
