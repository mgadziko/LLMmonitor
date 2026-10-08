# LLMmonitor

LLMmonitor is a native macOS app for keeping a clear, persistent view of the LLM machines on a local network. It is designed for a mixed fleet: Ollama hosts, OpenAI-compatible `llama-server` instances, and LM Studio servers can all appear in one place.

The app answers the practical questions quickly: which machines are reachable, what service each one is running, which models it reports, and when it was last seen. A remembered machine remains in the library when it is offline, along with its last-known model inventory.

## How it works

**Discovery** scans the active IPv4 `/24` subnet on the ports commonly used by the fleet: 11434, 11435, 1234, and 8080. It identifies responding services without sending prompts, credentials, or any request that changes server state.

**Inventory polling** uses read-only HTTP endpoints:

- Ollama: `GET /api/tags`
- OpenAI-compatible servers: `GET /v1/models`
- llama-server compatibility: accepts both the normal `data` response and its `models` response
- LM Studio: `GET /api/v0/models`

Known fleet addresses are given their machine names automatically. Other hosts can be added by hand, with a name, address, port, and server type.

## Library and export

The left Library table can be sorted by **Machine** or **IP Address**. The main table provides a fleet-wide view of status, server type, endpoint, reported models, and last-seen time.

Choose **File → Save…** to export the current machine table as either CSV or a readable plain-text report. The app does not export credentials because it does not collect them.

## Build and run

```sh
./Scripts/build-app.sh
open dist/LLMmonitor.app
```

The build script creates a standard application bundle, embeds the icon, stamps the About window with the package timestamp, and writes the result to `dist/LLMmonitor.app`. The project targets macOS 14 or later.

For Xcode development, open `LLMmonitor.xcodeproj` and choose the **LLMmonitor** scheme. Xcode builds the same application target and stamps the About build number during each build.

## Local data

The machine library is stored at:

```text
~/Library/Application Support/LLMmonitor/machines.json
```
