//
//  TranscriptionEngine.swift
//  wispr
//
//  Protocol abstracting the speech-to-text engine so the app
//  is decoupled from any specific ASR backend (WhisperKit, FluidAudio, etc.).
//

import Foundation

/// Abstract interface for any on-device speech-to-text engine.
///
/// Conforming types must be actors to guarantee thread-safe access
/// to model state and transcription resources.
protocol TranscriptionEngine: Actor {

    // MARK: - Model Management

    /// Returns the list of models this engine supports.
    func availableModels() -> [ModelInfo]

    /// Downloads a model with progress reporting.
    func downloadModel(_ model: ModelInfo) -> AsyncThrowingStream<DownloadProgress, Error>

    /// Deletes a downloaded model from disk.
    func deleteModel(_ modelName: String) async throws

    /// Loads a downloaded model into memory, making it ready for transcription.
    func loadModel(_ modelName: String) async throws

    /// Unloads the current model and loads a different one.
    func switchModel(to modelName: String) async throws

    /// Checks whether a downloaded model's files are intact.
    func validateModelIntegrity(_ modelName: String) async throws -> Bool

    /// Returns the current status of a model (not downloaded, downloading, downloaded, active).
    func modelStatus(_ modelName: String) -> ModelStatus

    /// Returns the name of the currently loaded model, or nil if none is loaded.
    func activeModel() -> String?

    /// Attempts to reload the active model with exponential backoff retry.
    func reloadModelWithRetry(maxAttempts: Int) async throws

    // MARK: - Batch Transcription

    /// Transcribes a complete audio buffer to text.
    func transcribe(
        _ audioSamples: [Float],
        language: TranscriptionLanguage
    ) async throws -> TranscriptionResult

    // MARK: - Streaming Transcription

    /// Accepts a stream of audio chunks and yields partial transcription results
    /// as they become available.
    ///
    /// Engines that don't support true streaming should accumulate all chunks
    /// and yield a single final result when the input stream finishes.
    func transcribeStream(
        _ audioStream: AsyncStream<[Float]>,
        language: TranscriptionLanguage
    ) -> AsyncThrowingStream<TranscriptionResult, Error>
}

// MARK: - Default Parameter Convenience

extension TranscriptionEngine {
    /// Convenience overload with default retry count.
    func reloadModelWithRetry() async throws {
        try await reloadModelWithRetry(maxAttempts: 3)
    }
}
