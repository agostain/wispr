# Wispr

A macOS suite for on-device speech-to-text powered by [OpenAI Whisper](https://github.com/openai/whisper) and [NVIDIA Parakeet](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/intro.html).

All transcription runs entirely on-device — your audio never leaves your Mac.

---

## Apps

### Wispr — Hotkey Dictation

A menu bar app that transcribes your speech and inserts the text at the cursor whenever you press a hotkey.

**Features:**
- **Hotkey-triggered dictation** — press a shortcut to start/stop recording; transcribed text is inserted at the cursor
- **Dual engine architecture** — choose between OpenAI Whisper and NVIDIA Parakeet through a unified interface
- **Multiple models** — Whisper Tiny (~75 MB) to Large v3 (~3 GB), Parakeet V3 (~400 MB), and Realtime 120M (~150 MB)
- **Low-latency streaming** — Parakeet Realtime 120M provides end-of-utterance detection for near-instant results (English)
- **Model management** — download, activate, switch, and delete models from a single UI
- **Multi-language support** — Whisper supports 90+ languages, Parakeet V3 supports 25 languages
- **Menu bar native** — lives in your menu bar, stays out of the way
- **Onboarding flow** — guided setup for permissions, model selection, and a test dictation
- **Accessibility-first** — full keyboard navigation, VoiceOver support, and high-contrast mode

### WisprLive — Live Meeting Transcription

A companion app that captures both your microphone and system audio simultaneously, transcribing conversations in real time into a live, scrollable transcript.

**Features:**
- **Dual-channel capture** — records mic and system audio in parallel, transcribing each as a separate speaker
- **Live scrolling transcript** — timestamped entries auto-scroll as speech is recognized
- **Per-app audio filter** — scope system audio capture to a single app (e.g. Zoom, Teams) during a session; picker updates dynamically as apps open and close
- **Automatic filter fallback** — if the filtered app quits mid-session, WisprLive automatically falls back to all system audio and shows a warning
- **Echo cancellation** — optional processing to reduce microphone bleed from speakers
- **Transcript persistence** — sessions are saved to disk automatically; open the save folder from the toolbar
- **Configurable hotkey** — start/stop sessions with a keyboard shortcut
- **Sleep/wake handling** — capture stops cleanly when the Mac sleeps; the session auto-saves and can be resumed manually on wake
- **Floating window** — transcript window can be pinned above other apps

---

## Models

| Model | Engine | Size | Streaming | Languages | Notes |
|-------|--------|------|-----------|-----------|-------|
| Tiny | Whisper | ~75 MB | No | 90+ | Fastest, lower accuracy |
| Base | Whisper | ~140 MB | No | 90+ | Good balance for quick tasks |
| Small | Whisper | ~460 MB | No | 90+ | Solid general-purpose |
| Medium | Whisper | ~1.5 GB | No | 90+ | High accuracy |
| Large v3 | Whisper | ~3 GB | No | 90+ | Best Whisper accuracy |
| Parakeet V3 | Parakeet | ~400 MB | No | 25 | Fast, high accuracy, multilingual |
| Realtime 120M | Parakeet | ~150 MB | Yes | English | Low-latency with end-of-utterance detection |

---

## Installation

### Building from Source

Requires macOS 15.0+ and Xcode 16+.

1. Clone the repo
2. Open `wispr.xcodeproj` in Xcode
3. Select the `wispr` or `wisprlive` scheme
4. Build and run (⌘R)
5. Follow the onboarding flow to grant permissions and download a model

---

## Requirements

- macOS 15.0+
- Microphone permission (both apps)
- Screen Recording permission (WisprLive — required for system audio capture via ScreenCaptureKit)

---

## Architecture

### Wispr

| Layer | Path | Description |
|-------|------|-------------|
| Models | `wispr/Models/` | Data types — model info, permissions, app state, errors |
| Services | `wispr/Services/` | Core logic — audio engine, Whisper/Parakeet integration, hotkey monitoring, settings |
| UI | `wispr/UI/` | SwiftUI views — menu bar, recording overlay, settings, onboarding |
| Utilities | `wispr/Utilities/` | Logging, theming, SF Symbols, preview helpers |

The app uses a `CompositeTranscriptionEngine` that routes to the correct backend (`WhisperService` or `ParakeetService`) based on the selected model. Both engines conform to a shared `TranscriptionEngine` protocol, so switching between them is seamless.

### WisprLive

| Layer | Path | Description |
|-------|------|-------------|
| Models | `wisprlive/Models/` | `TranscriptEntry`, `Speaker`, `AudioApp` |
| Services | `wisprlive/Services/` | `DualAudioCapture`, `MicAudioCapture`, `SystemAudioCapture`, `LiveStateManager`, `TranscriptStore`, `LiveSettingsStore` |
| UI | `wisprlive/UI/` | Menu bar controller, transcript window, toolbar, settings, onboarding |
| Utilities | `wisprlive/Utilities/` | Structured logging |

`DualAudioCapture` runs mic and system audio pipelines in parallel as Swift actors. `SystemAudioCapture` uses ScreenCaptureKit (`SCStream`) for system audio; it supports per-app `SCContentFilter` for scoping capture to a single application. `LiveStateManager` coordinates both pipelines, applies transcription, and manages state transitions (`idle` / `capturing` / `error`).

---

## License

This project is licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
