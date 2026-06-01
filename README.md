# MacOmniVoice

A native macOS SwiftUI app for **[OmniVoice](https://github.com/k2-fsa/OmniVoice)** — a state-of-the-art massively multilingual zero-shot TTS model supporting 600+ languages and voice cloning.

Designed to feel like a regular Mac app while delegating inference to the official `omnivoice` Python package under the hood.

## Features

- 🎙️ **Voice cloning** — drop in a 3–10 s reference clip, type some text, hit Generate
- 🤖 **Auto setup** — first run creates a private Python venv and installs `omnivoice` + PyTorch
- 📦 **Auto model download** — pulls `k2-fsa/OmniVoice` from HuggingFace on first synthesis
- 🔄 **Update check** — compares your local snapshot against the HF Hub head commit
- ⚡ **Apple Silicon support** — uses the PyTorch `mps` backend by default
- 🎛️ **Advanced controls** — reference text, language, instruct, speed, duration override, inference steps, denoise, CFG / guidance scale, t-shift, layer/position/class temperatures, pre-process prompt, post-process output
- 🔊 **Built-in player** with scrub, save, reveal in Finder

## Requirements

- macOS 14 or newer (Apple Silicon recommended)
- A host Python ≥ 3.10 available on PATH (Homebrew `python@3.11`, python.org installer, or Xcode CLT all work)
- ~6 GB free disk space (PyTorch + model)
- Internet on first run to install dependencies and download the model

The app **never modifies your system Python**. All Python deps land in a dedicated venv at:
```
~/Library/Application Support/MacOmniVoice/venv
```
Model weights cache in the standard `~/.cache/huggingface` location.

## Build & Run

```bash
# Quick run (debug):
swift run

# Build a real .app bundle:
./Scripts/build-app.sh           # release
CONFIG=debug ./Scripts/build-app.sh

open build/MacOmniVoice.app
# or
cp -R build/MacOmniVoice.app /Applications/
```

## First-run flow

1. Launch app → setup screen verifies a host Python ≥ 3.10
2. Click **Install OmniVoice** — log streams as the venv is created and PyTorch + `omnivoice` install (~3–5 GB, several minutes)
3. Main screen appears with model status. Click **Download** once to pull the ~1 GB model from HuggingFace (or on first Generate, it downloads lazily via `from_pretrained`)
4. Type text, pick a reference WAV/MP3, click **Generate**

A persistent Python subprocess keeps the model warm between requests — only the first generate pays the model-load cost.

## Architecture

```
┌──────────────────────────────┐
│   SwiftUI app (MacOmniVoice) │
│   ─ MainView, AdvancedView   │
│   ─ AppState, AppSettings    │
│   ─ AudioPlayerService       │
└──────────────┬───────────────┘
               │ JSON-line protocol over pipes
               ▼
┌──────────────────────────────┐
│ omnivoice_runner.py (Python) │
│   ─ loads OmniVoice once     │
│   ─ serves synth requests    │
│   ─ reports model_info / dl  │
└──────────────────────────────┘
               │
               ▼
        PyTorch + omnivoice + HuggingFace Hub
```

Communication contract (one JSON object per line):
| Action       | Purpose                                |
|--------------|----------------------------------------|
| `ping`       | health check                           |
| `load`       | `from_pretrained(model_id)`            |
| `synthesize` | `model.generate(**kwargs)` → WAV       |
| `download`   | `snapshot_download(model_id)`          |
| `model_info` | report cached revision / size on disk  |
| `quit`       | graceful shutdown                      |

All advanced parameters are passed through verbatim; `omnivoice_runner.py` filters them against the live `model.generate()` signature so the app stays compatible across `omnivoice` versions that add or rename kwargs.

## Repo layout

```
MacOmniVoice/
├── Package.swift
├── Scripts/build-app.sh
├── Sources/MacOmniVoice/
│   ├── MacOmniVoiceApp.swift            ← @main
│   ├── AppState.swift                   ← top-level glue
│   ├── Models/
│   │   ├── AppSettings.swift            ← persisted prefs (UserDefaults)
│   │   └── SynthesisRequest.swift       ← request → Python kwargs
│   ├── Services/
│   │   ├── PythonRuntime.swift          ← venv setup + long-lived runner
│   │   ├── ModelManager.swift           ← HF Hub update check
│   │   ├── SynthesisEngine.swift        ← orchestrator + event pump
│   │   └── AudioPlayerService.swift     ← AVAudioPlayer wrapper
│   ├── Views/
│   │   ├── RootView.swift               ← stage router
│   │   ├── SetupView.swift              ← first-run install UI
│   │   ├── MainView.swift               ← main synthesis screen
│   │   ├── AdvancedSettingsView.swift   ← all the knobs
│   │   ├── ModelStatusBar.swift        ← model up-to-date banner
│   │   ├── OutputPlayerCard.swift       ← play / scrub / save
│   │   └── ConsolePanel.swift           ← runner log
│   └── Resources/
│       └── omnivoice_runner.py          ← Python bridge
└── README.md
```

## Tips

- Use a 3–10 s reference clip, ideally in the same language as the target text
- Leave **Reference text** blank to let Whisper auto-transcribe (slower first call)
- Lower **Inference steps** to 16 for ~2× faster generation with mild quality loss
- For voice *design* instead of cloning, fill **Instruct** (e.g. `female, british accent`) and leave reference audio blank
- If HuggingFace is unreachable, launch with `MACOMNIVOICE_HF_MIRROR=1 open build/MacOmniVoice.app` to use `hf-mirror.com`

## License

App code: Apache-2.0 (matches OmniVoice). See the upstream [OmniVoice repository](https://github.com/k2-fsa/OmniVoice) for the model and inference library license.
