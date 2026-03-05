# NVIDIA Parakeet Integration Analysis

## Context

This analysis evaluates the feasibility of adding NVIDIA Parakeet ASR model support to Wispr, which currently uses WhisperKit as its sole speech-to-text engine.

## Why It's Not a Drop-In

Parakeet and Whisper are fundamentally different architectures:
- **Whisper**: encoder-decoder (seq2seq) transformer
- **Parakeet**: FastConformer encoder + Token-and-Duration Transducer (TDT) decoder

WhisperKit is purpose-built for Whisper models only. You cannot load a Parakeet model into WhisperKit.

## Current WhisperKit Coupling Points

The integration runs deep across the codebase:

| Area | Coupling |
|------|----------|
| `WhisperService` | Direct use of `WhisperKit`, `WhisperKitConfig`, `DecodingOptions` types |
| Model downloads | Uses `WhisperKit.download(variant:)` and its HuggingFace Hub integration |
| Model storage | Assumes `argmaxinc/whisperkit-coreml/` directory structure |
| `AudioEngine` | Tuned for WhisperKit's 16kHz mono Float32 input format |
| `StateManager` | Calls `whisperService.transcribe()` directly — no abstraction layer |
| UI (model mgmt, onboarding, settings) | All reference "Whisper" models by name |
| `TranscriptionResult` / `TranscriptionLanguage` | Shaped around Whisper's output format |

## Integration Paths

### Path 1: Argmax Pro SDK (medium effort, paid)

Argmax (the WhisperKit authors) already optimized Parakeet v2/v3 for Apple Silicon ANE in their Pro SDK. Similar API surface to WhisperKit.

- **Pros**: Battle-tested, same vendor as WhisperKit, familiar patterns
- **Cons**: Paid at ~$0.42/device/month, changes app economics
- **Effort**: ~2-3 weeks
- **Link**: https://www.argmaxinc.com/blog/nvidia-frontier-speech-models-on-argmax-sdk

### Path 2: FluidAudio (medium effort, free) ← Recommended

Open-source Swift SDK with Parakeet TDT v3 running on CoreML/ANE. MIT/Apache 2.0 licensed. Supports 25 European languages. ~110× RTF on M4 Pro.

- **Pros**: Free, open-source, already optimized for ANE, clean Swift API, active community
- **Cons**: Younger project, less battle-tested than Argmax Pro
- **Effort**: ~3-4 weeks
- **Link**: https://github.com/FluidInference/FluidAudio

### Path 3: DIY CoreML Conversion (high effort)

Convert PyTorch weights to CoreML yourself and write the full inference pipeline in Swift (FastConformer encoder, TDT decoder, beam search, tokenizer, post-processing).

- **Pros**: Full control, no external dependencies
- **Cons**: Months of work, reimplements what FluidAudio already does
- **Effort**: 2-3 months
- **Not recommended**

## Required Refactoring (Any Path)

1. **Introduce `TranscriptionEngine` protocol** — abstract interface that both `WhisperService` and a new `ParakeetService` conform to
2. **Create `ParakeetService` actor** — mirrors `WhisperService` interface but wraps FluidAudio (or Argmax Pro)
3. **Refactor `StateManager`** — work against the protocol instead of `WhisperService` directly
4. **Update `AudioEngine`** — verify Parakeet's expected audio format (may differ from WhisperKit's 16kHz mono Float32)
5. **Overhaul model management UI** — support two model families with different download sources, sizes, and capabilities
6. **Update onboarding flow** — let users choose engine/model family during setup
7. **Update `SettingsStore`** — persist selected engine type alongside model name

## Parakeet vs Whisper: Key Differences

| | Whisper | Parakeet TDT v3 |
|---|---------|-----------------|
| Architecture | Encoder-decoder transformer | FastConformer + TDT |
| Parameters | 39M–1.5B (tiny→large) | 600M |
| Languages | 99 | 25 (European) |
| Speed | ~2-5× RTF (large-v3) | ~110× RTF on M4 Pro |
| Accuracy | Strong baseline | Tops OpenASR leaderboard |
| Model size | 75MB–3GB | ~400MB (compressed) to ~1.2GB |
| License | MIT | CC-BY-4.0 |

## Difficulty Rating: 6/10

Not trivial due to deep WhisperKit coupling, but the architecture is clean enough that the abstraction refactor is well-defined. The hardest part is the model management UX for two different model families.

## Recommendation

Use **FluidAudio (Path 2)**. Add it as an SPM dependency, create a `ParakeetService` actor, and introduce a `TranscriptionEngine` protocol to decouple `StateManager` from any specific ASR backend. This keeps the app free/open-source and gives users a choice between Whisper (broad language support) and Parakeet (superior speed and accuracy for European languages).
