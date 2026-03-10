# Requirements: Hands-Free Dictation

## Requirement 1: Toggle-Based Recording Mode Setting

**User Story:** As a user, I want to switch between push-to-talk and hands-free dictation modes so I can choose the interaction style that suits my workflow.

**Acceptance Criteria:**
- A `handsFreeMode` boolean setting exists in `SettingsStore`, defaulting to `false` (push-to-talk).
- The setting persists across app launches via UserDefaults.
- A toggle labeled "Hands-Free Mode" is visible in the Settings view under the hotkey section.
- The toggle includes an accessibility hint describing both modes.
- Restoring defaults resets `handsFreeMode` to `false`.

## Requirement 2: Hands-Free Hotkey Behavior

**User Story:** As a user with hands-free mode enabled, I want to press the hotkey once to start recording and press it again to stop, so I don't have to hold the key during long dictation.

**Acceptance Criteria:**
- When `handsFreeMode` is `true`, a hotkey key-down event while idle starts recording.
- When `handsFreeMode` is `true`, a hotkey key-up event is ignored (no-op).
- When `handsFreeMode` is `true`, a hotkey key-down event while recording stops recording and triggers transcription.
- Hotkey toggles during `.loading`, `.processing`, or `.error` states are safely ignored.
- Push-to-talk behavior (hold to record, release to stop) is unchanged when `handsFreeMode` is `false`.

## Requirement 3: End-of-Utterance Auto-Stop

**User Story:** As a user with an EOU-capable model, I want recording to automatically stop when I finish speaking, so I don't need to press the hotkey a second time.

**Acceptance Criteria:**
- After recording starts in hands-free mode, the app checks if the active transcription engine supports EOU detection.
- If EOU is supported, a background monitoring task consumes the `transcribeStream` output.
- When a `TranscriptionResult` with `isEndOfUtterance: true` is received, recording auto-stops, text is inserted, and state returns to `.idle`.
- If EOU is not supported, no monitoring task is created and the user must manually toggle recording off.
- The EOU monitoring task is cancellable and is cancelled if the user manually stops recording.

## Requirement 4: TranscriptionResult EOU Flag

**User Story:** As a developer, I need a clear signal from the transcription engine indicating end-of-utterance so the StateManager can react accordingly.

**Acceptance Criteria:**
- `TranscriptionResult` includes an `isEndOfUtterance: Bool` property, defaulting to `false`.
- Existing call sites are unaffected by the new property (default value preserves backward compatibility).
- Only the EOU-capable engine (`ParakeetService` with the Parakeet EOU model) sets `isEndOfUtterance` to `true`.
- `WhisperService` never sets `isEndOfUtterance` to `true`.

## Requirement 5: Engine EOU Capability Query

**User Story:** As a developer, I need each transcription engine to declare whether it supports EOU detection so the StateManager can decide whether to enable auto-stop.

**Acceptance Criteria:**
- `TranscriptionEngine` protocol includes a required `supportsEndOfUtteranceDetection() async -> Bool` method with no default implementation.
- `WhisperService` returns `false`.
- `ParakeetService` returns `true` only when the Parakeet EOU model is loaded and the EOU manager is initialized.
- `CompositeTranscriptionEngine` forwards the call to the active engine, returning `false` if no engine is active.

## Requirement 6: Graceful EOU Monitoring Failure

**User Story:** As a user, I want recording to continue uninterrupted if EOU monitoring encounters an error, so I can still stop manually.

**Acceptance Criteria:**
- If `transcribeStream` throws an error during EOU monitoring, the error is logged as a warning.
- Recording continues and the user can still press the hotkey to stop.
- The app does not crash or enter an error state due to EOU monitoring failure.

## Requirement 7: Recording Overlay Accessibility

**User Story:** As a VoiceOver user, I want the recording overlay to tell me how to stop recording based on the active mode.

**Acceptance Criteria:**
- In hands-free mode, the overlay's accessibility hint says "Press the hotkey again to stop recording, or wait for auto-stop."
- In push-to-talk mode, the overlay's accessibility hint says "Release the hotkey to stop recording."
- The hint updates immediately when the mode changes.
