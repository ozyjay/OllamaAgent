# OllamaDashboard

OllamaDashboard is a local macOS SwiftUI utility app with a lightweight menu bar companion for an existing Ollama service. It attaches to the public Ollama HTTP API at `http://localhost:11434` by default and keeps optional CLI-backed controls explicit and opt-in.

The app is designed as a lightweight local systems dashboard for:

- Ollama service reachability and version
- installed models from `/api/tags`
- loaded/running models from `/api/ps`
- model warm up, keep-alive refresh, and unloading
- model-aware app-side runtime profiles
- context test prompts
- simple benchmark timing
- bounded read-only logs and optional service configuration notes
- optional localhost proxy for tracking active external Ollama requests

The main window opens on launch and is the primary workspace. Closing the window leaves the app running so the menu bar companion, proxy, and background refresh can continue; use Quit from the app menu or menu bar companion to stop it.

## Run

Open `OllamaDashboard.xcodeproj` in Xcode 26 or newer and run the `OllamaDashboard` scheme.

Requirements:

- macOS 13.0 or newer
- Xcode 26 or newer
- Ollama running locally, usually at `http://localhost:11434`

From PowerShell (`pwsh`):

```powershell
./scripts/build.ps1
./scripts/run.ps1
```

`run.ps1` builds first if the app is not already present in `.DerivedData`.

To install the app into `~/Applications`:

```powershell
./scripts/install.ps1
```

To install and launch it:

```powershell
./scripts/install.ps1 -Launch
```

To install somewhere else, pass a destination folder:

```powershell
./scripts/install.ps1 -Destination /Applications
```

## Features

- Logs: reachable/offline state, version, base URL, last refresh, local URL/docs buttons, proxy status, logs, and optional service configuration notes.
- Profiles: editable built-in presets with fallback context policies and exact per-model context overrides.
- Models: installed model search/sort/details, Idle/Warm/Busy status with remaining keep-alive time, last warm-up profile used, warm up for any installed model, copy model name, and unload warm models with confirmation.
- Settings: base URL, refresh interval, CLI enablement, CLI path, local proxy, diagnostics notes, and confirmations.

## MVP Limits

- Attaches to an existing Ollama service.
- Does not start or manage `ollama serve`.
- Does not delete, pull, or create models.
- Does not change `launchctl` or require admin privileges.
- Does not send data to external services.

## API vs CLI

API-backed features use Ollama's public `/api` endpoints: version, tags, ps, show, generate, warming, unloading by `keep_alive: 0`, and benchmark timing.

CLI-backed controls are opt-in: `ollama stop` and raw `ollama ps`. Model names are validated and passed to `Process` as arguments, not interpolated into shell commands.

The Logs view reads `~/.ollama/logs/server.log` directly and only loads the final bounded slice of the file before showing the last 200 lines.

Proxy mode is optional. When enabled, point compatible clients at the dashboard proxy URL, for example `http://localhost:11435`, instead of the Ollama base URL. The proxy forwards requests to Ollama and marks proxied models as Busy while responses are in flight.

## Manual Ollama Configuration

When enabled in Settings, the Logs diagnostics area lists common environment variables and copyable commands such as:

```powershell
launchctl setenv OLLAMA_CONTEXT_LENGTH <value>
```

Restarting Ollama may be required for service configuration changes to take effect.

## Tests

The test target includes fixtures for Ollama API response parsing, benchmark timing calculations, model name validation, settings defaults, and profile persistence.

From PowerShell (`pwsh`):

```powershell
./scripts/test.ps1
```

## Roadmap

- Pull model.
- Model deletion with strong confirmation.
- Modelfile variants and templates.
- Managed Ollama mode.
- Notifications when models unload.
- Live menu-bar tokens/sec monitor.
- Diagnostics export.
