# TranscriptionEngine Protocol — Refactoring Plan

## Goal

Introduce a `TranscriptionEngine` protocol that abstracts the speech-to-text backend, then make `WhisperService` conform to it. Every file that currently depends on the concrete `WhisperService` type will be updated to depend on the protocol instead. This decouples the app from WhisperKit and prepares the codebase for adding alternative engines (e.g. Parakeet via FluidAudio) later.

No functional changes. The app behaves identically after this refactor.

## The Protocol

```swift
/// Abstract interface for any on-device speech-to-text engine.
protocol TranscriptionEngine: Actor {
    // -- Model management --
    func availableModels() -> [ModelInfo]
    func downloadModel(_ model: ModelInfo) -> AsyncThrowingStream<DownloadProgress, Error>
    func deleteModel(_ modelName: String) async throws
    func loadModel(_ modelName: String) async throws
    func switchModel(to modelName: String) async throws
    func validateModelIntegrity(_ modelName: String) async throws -> Bool
    func modelStatus(_ modelName: String) -> ModelStatus
    func activeModel() -> String?
    func reloadModelWithRetry(maxAttempts: Int) async throws

    // -- Batch transcription (current behavior) --
    func transcribe(_ audioSamples: [Float], language: TranscriptionLanguage) async throws -> TranscriptionResult

    // -- Streaming transcription (future-proofing) --
    /// Accepts a stream of audio chunks and yields partial transcription results
    /// as they become available. Engines that don't support true streaming can
    /// accumulate all chunks and yield a single final result.
    func transcribeStream(
        _ audioStream: AsyncStream<[Float]>,
        language: TranscriptionLanguage
    ) -> AsyncThrowingStream<TranscriptionResult, Error>
}
```

### Rename `WhisperModelInfo` → `ModelInfo`

The existing `WhisperModelInfo` struct is already engine-agnostic in its fields — only the name ties it to Whisper. We rename it to `ModelInfo` so the protocol and all consumers are fully provider-neutral.

```swift
// wispr/Models/ModelInfo.swift  (renamed from WhisperModelInfo.swift)
struct ModelInfo: Identifiable, Sendable, Equatable {
    let id: String              // e.g. "tiny", "parakeet-tdt-v3"
    let displayName: String     // e.g. "Tiny", "Parakeet TDT v3"
    let sizeDescription: String // e.g. "~75 MB"
    let qualityDescription: String // e.g. "Fastest, lower accuracy"
    var status: ModelStatus
}
```

This is a mechanical rename — every file that references `WhisperModelInfo` gets updated to `ModelInfo`. We use `semanticRename` to handle this automatically across the codebase.

### Design Decisions

1. **`protocol TranscriptionEngine: Actor`** — WhisperService is already an actor. Constraining the protocol to `Actor` means conforming types are automatically `Sendable` and callers use `await` naturally. No existential wrapper needed.

2. **Provider-agnostic model types** — `WhisperModelInfo` is renamed to `ModelInfo`. The other shared types (`DownloadProgress`, `TranscriptionResult`, `TranscriptionLanguage`, `ModelStatus`) are already engine-agnostic and stay as-is. When Parakeet is added later, these types will be reused (possibly with minor extensions like an `engineFamily` field on `ModelInfo`).

3. **`any TranscriptionEngine`** — All consumer sites will use `any TranscriptionEngine` (existential) rather than generics. This keeps the code simple — no generic parameter threading through 10+ files. The performance cost of existential dispatch is negligible for this use case (UI and infrequent service calls).

4. **Streaming transcription** — `transcribeStream(_:language:)` takes an `AsyncStream<[Float]>` of audio chunks and returns an `AsyncThrowingStream<TranscriptionResult, Error>` of partial results. This future-proofs the protocol for real-time engines (Parakeet, future WhisperKit streaming) without requiring any caller changes today. The `WhisperService` conformance will provide a simple default implementation that collects all chunks and calls the batch `transcribe()` method once the input stream finishes — identical to current behavior. A future Parakeet engine could emit partial `TranscriptionResult` values as audio arrives, enabling live-preview UX.

5. **File location** — The protocol goes in `wispr/Services/TranscriptionEngine.swift`, next to `WhisperService.swift`.

## Files to Change

### Phase 1: Define the protocol, rename model type, and conform WhisperService

| File | Change |
|------|--------|
| `wispr/Models/WhisperModelInfo.swift` | Rename file to `ModelInfo.swift` via `smartRelocate`. Rename the struct from `WhisperModelInfo` to `ModelInfo` via `semanticRename`. This propagates across the entire codebase automatically. |
| `wispr/Services/TranscriptionEngine.swift` | **New file.** Define the `TranscriptionEngine` protocol using `ModelInfo`. |
| `wispr/Services/WhisperService.swift` | Add `extension WhisperService: TranscriptionEngine {}`. The existing public API already matches the protocol for all methods except `transcribeStream`, which gets a simple implementation that collects all chunks from the input stream and delegates to the batch `transcribe()` method. Method signatures now use `ModelInfo` instead of `WhisperModelInfo` (handled by the rename in step 1). |

### Phase 2: Update consumers to use the protocol

| File | Current type | New type | Notes |
|------|-------------|----------|-------|
| `wispr/Services/StateManager.swift` | `private let whisperService: WhisperService` | `private let whisperService: any TranscriptionEngine` | Init parameter changes too. Only calls `transcribe()` and `loadModel()`. |
| `wispr/wisprApp.swift` | `let whisperService = WhisperService()` | Keep concrete instantiation, but pass as `any TranscriptionEngine` to consumers. The `WisprAppDelegate` is the composition root — it's the one place that knows the concrete type. |
| `wispr/UI/MenuBarController.swift` | `private let whisperService: WhisperService` | `private let whisperService: any TranscriptionEngine` | Passes it to `SettingsView` and `ModelManagementView`. |
| `wispr/UI/Settings/SettingsView.swift` | `private let whisperService: WhisperService` | `private let whisperService: any TranscriptionEngine` | Calls `availableModels()`, `modelStatus()`. |
| `wispr/UI/ModelManagementView.swift` | `private let whisperService: WhisperService` | `private let whisperService: any TranscriptionEngine` | Calls `availableModels()`, `modelStatus()`, `switchModel()`, `deleteModel()`, `activeModel()`. |
| `wispr/UI/ModelDownloadProgressView.swift` | `private let whisperService: WhisperService` | `private let whisperService: any TranscriptionEngine` | Calls `downloadModel()`. |
| `wispr/UI/Onboarding/OnboardingFlow.swift` | `let whisperService: WhisperService` | `let whisperService: any TranscriptionEngine` | Passes to `OnboardingModelSelectionStep`. |
| `wispr/UI/Onboarding/OnboardingModelSelectionStep.swift` | `let whisperService: WhisperService` | `let whisperService: any TranscriptionEngine` | Calls `availableModels()`, `modelStatus()`, `activeModel()`, `loadModel()`. |

### Phase 3: Update preview helpers and tests

| File | Change |
|------|--------|
| `wispr/Utilities/PreviewHelpers.swift` | Change `makeWhisperService() -> WhisperService` to `makeWhisperService() -> any TranscriptionEngine`. The return value is still `WhisperService()` — only the declared return type changes. `sampleModels` type changes from `[WhisperModelInfo]` to `[ModelInfo]` automatically via the rename. |
| `wispr/UI/Onboarding/OnboardingPreview.swift` | Will work automatically once `OnboardingFlow` accepts `any TranscriptionEngine`. |
| `wisprTests/WhisperServiceTests.swift` | Keep testing the concrete `WhisperService` directly — these are unit tests for the WhisperKit integration specifically. |
| `wisprTests/RecordingOverlayTests.swift` | If it references `WhisperService`, update to use `any TranscriptionEngine` or keep concrete if it's just constructing a mock `StateManager`. |
| `wisprTests/AppLifecycleIntegrationTests.swift` | Same approach — update type annotations where `WhisperService` is passed to `StateManager`. |
| `wisprTests/EndToEndIntegrationTests.swift` | Same. |
| `wisprTests/MenuBarControllerTests.swift` | Same. |
| `wisprTests/MultiLanguageTests.swift` | Same. |

## Execution Order

1. Rename `WhisperModelInfo` → `ModelInfo` (file + type) using `smartRelocate` and `semanticRename`
2. Create `TranscriptionEngine.swift` with the protocol definition
3. Add conformance to `WhisperService` (including `transcribeStream` stub)
4. Update `StateManager` init and stored property
5. Update `wisprApp.swift` (composition root) — pass `whisperService` as `any TranscriptionEngine`
6. Update `MenuBarController` init and stored property
7. Update `SettingsView`, `ModelManagementView`, `ModelDownloadProgressView`
8. Update `OnboardingFlow`, `OnboardingModelSelectionStep`
9. Update `PreviewHelpers`
10. Update test files
11. Build and run tests

Each step should compile independently. If step N breaks the build, fix it before moving to step N+1.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `any TranscriptionEngine` existential can't be used with `some` parameter positions in older Swift | We target Swift 6 / macOS 26 — `any` existentials work fine with actor protocols. |
| Actor isolation mismatch when passing `any TranscriptionEngine` to `@MainActor` views | The protocol is `: Actor`, so callers already `await` all calls. Views store it as a plain `let` property (not `@State` or `@Environment`), same as today with `WhisperService`. No isolation issue. |
| Test files that create `WhisperService()` directly for integration tests | These stay as-is. Integration tests should test the real implementation. Only update the type annotations where `WhisperService` is passed to `StateManager` or UI components. |
| `reloadModelWithRetry(maxAttempts:)` has a default parameter value (`= 3`) | Protocol methods can't have default parameter values. Add an extension on `TranscriptionEngine` that provides the default: `extension TranscriptionEngine { func reloadModelWithRetry() async throws { try await reloadModelWithRetry(maxAttempts: 3) } }` |

## What This Does NOT Do

- Does not create a `MockTranscriptionEngine` for tests (can be added later when Parakeet work starts)
- Does not change any behavior — purely a type-level refactor plus a mechanical rename
- Does not touch `AudioEngine` (audio format concerns are a separate task for Parakeet integration)
