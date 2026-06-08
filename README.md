# OllamaDashboard

OllamaDashboard is a local macOS SwiftUI menu bar control panel for an existing Ollama service. It attaches to the public Ollama HTTP API at `http://localhost:11434` by default and keeps optional CLI-backed controls explicit and opt-in.

The app is designed as a lightweight local systems dashboard for:

- Ollama service reachability and version
- installed models from `/api/tags`
- loaded/running models from `/api/ps`
- model warming and unloading
- app-side runtime profiles
- context test prompts
- simple benchmark timing
- optional read-only logs and service configuration notes

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

- Service status: reachable/offline state, version, base URL, last refresh, local URL/docs buttons.
- Installed models: refresh, search, sort, digest/size/date display, and `/api/show` details.
- Running models: refresh, copy model name, warm selected model, unload selected model with confirmation.
- Context: run a test prompt with a selected `num_ctx` value.
- Benchmark: run prompt presets and show timing stats when Ollama returns them.
- Profiles: editable built-in presets for Coding - Conservative, Long Context, and Low RAM.
- Settings: base URL, refresh interval, CLI enablement, CLI path, logs, and confirmations.
- Advanced: read-only log viewer and copyable `launchctl setenv` examples.

## MVP Limits

- Attaches to an existing Ollama service.
- Does not start or manage `ollama serve`.
- Does not delete, pull, or create models.
- Does not change `launchctl` or require admin privileges.
- Does not send data to external services.

## API vs CLI

API-backed features use Ollama's public `/api` endpoints: version, tags, ps, show, generate, warming, unloading by `keep_alive: 0`, and benchmark timing.

CLI-backed features are opt-in: `ollama stop`, raw `ollama ps`, and reading `~/.ollama/logs/server.log`. Model names are validated and passed to `Process` as arguments, not interpolated into shell commands.

## Manual Ollama Configuration

The Service Configuration panel lists common environment variables and copyable commands such as:

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
