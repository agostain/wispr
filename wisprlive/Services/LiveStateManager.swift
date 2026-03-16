//
//  LiveStateManager.swift
//  wisprlive
//
//  State machine for WisprLive: .idle / .capturing / .error(String)
//  Orchestrates DualAudioCapture and two transcription pipeline tasks.
//

import Foundation
import Observation
import ScreenCaptureKit
import WisprKit
import os

/// App state for WisprLive.
enum LiveAppState: Equatable {
    case idle
    case capturing
    case error(String)
}

@MainActor
@Observable
final class LiveStateManager {

    // MARK: - Observed State

    var appState: LiveAppState = .idle
    /// Non-nil when a non-fatal warning is active (e.g. mic disconnected).
    var warningBadge: String? = nil
    /// Seconds elapsed since the current capture session started.
    var elapsedSeconds: TimeInterval = 0
    /// Whether the mic pipeline is actively buffering (used by live indicator).
    var micListening: Bool = false
    /// Whether the system audio pipeline is actively buffering.
    var remoteListening: Bool = false
    /// nil = all system audio; non-nil = specific app filter
    var selectedAudioApp: AudioApp? = nil
    /// Apps available for per-app filtering. Populated on demand.
    var availableAudioApps: [AudioApp] = []

    // MARK: - Dependencies

    private let transcriptionEngine: any TranscriptionEngine
    private let transcriptStore: TranscriptStore
    private let settingsStore: LiveSettingsStore
    private let dualAudio: DualAudioCapture

    // MARK: - Session State

    private var sessionStartTime: Date?
    private var errorDismissTask: Task<Void, Never>?
    private var elapsedTimerTask: Task<Void, Never>?
    private var micPipelineTask: Task<Void, Never>?
    private var remotePipelineTask: Task<Void, Never>?

    // MARK: - Init

    init(
        transcriptionEngine: any TranscriptionEngine,
        transcriptStore: TranscriptStore,
        settingsStore: LiveSettingsStore,
        dualAudio: DualAudioCapture
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.transcriptStore = transcriptStore
        self.settingsStore = settingsStore
        self.dualAudio = dualAudio
    }

    // MARK: - Control

    func startCapture() async {
        guard appState == .idle else { return }
        appState = .capturing
        sessionStartTime = Date()
        warningBadge = nil
        transcriptStore.clear()
        startElapsedTimer()

        do {
            var systemFilter: Any? = nil
            if #available(macOS 15.0, *), let app = selectedAudioApp {
                if let content = try? await SCShareableContent.current,
                   let scApp = content.applications.first(where: { $0.bundleIdentifier == app.bundleIdentifier }),
                   let display = content.displays.first {
                    systemFilter = SCContentFilter(display: display, including: [scApp], exceptingWindows: []) as Any
                } else {
                    warningBadge = "Could not filter to '\(app.name)' — using all system audio"
                }
            }
            let streams = try await dualAudio.start(
                echoCancellation: settingsStore.echoCancellationEnabled,
                systemFilter: systemFilter
            )
            startMicPipeline(stream: streams.micStream)
            startRemotePipeline(stream: streams.systemStream)
        } catch {
            await handleError(error.localizedDescription)
        }
    }

    func stopCapture() async {
        guard appState == .capturing else { return }
        cancelPipelines()
        await dualAudio.stop()
        let duration = elapsedSeconds
        let startTime = sessionStartTime ?? Date()
        appState = .idle
        elapsedSeconds = 0
        sessionStartTime = nil
        micListening = false
        remoteListening = false
        // Auto-save transcript
        if !transcriptStore.entries.isEmpty {
            try? await transcriptStore.save(
                startTime: startTime,
                duration: duration,
                language: settingsStore.languageMode
            )
        }
    }

    /// Transitions to `.error` and auto-dismisses to `.idle` after 5 seconds.
    func handleError(_ message: String) async {
        cancelPipelines()
        await dualAudio.stop()
        // Auto-save partial transcript if session had any content
        if !transcriptStore.entries.isEmpty, let startTime = sessionStartTime {
            try? await transcriptStore.save(
                startTime: startTime,
                duration: elapsedSeconds,
                language: settingsStore.languageMode
            )
        }
        appState = .error(message)
        elapsedSeconds = 0
        sessionStartTime = nil
        micListening = false
        remoteListening = false
        errorDismissTask?.cancel()
        errorDismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard let self, case .error = self.appState else { return }
            self.appState = .idle
        }
    }

    // MARK: - Audio Filter

    /// Fetches the list of running apps available as audio sources.
    /// Only meaningful on macOS 15+. No-op on earlier versions.
    func fetchAudioApps() async {
        guard #available(macOS 15.0, *) else { return }
        guard let content = try? await SCShareableContent.current else { return }
        availableAudioApps = content.applications
            .filter { !$0.bundleIdentifier.isEmpty && !$0.applicationName.isEmpty }
            .map { AudioApp(bundleIdentifier: $0.bundleIdentifier, name: $0.applicationName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Switches the system audio source. Safe to call mid-session or before starting.
    func switchAudioFilter(to app: AudioApp?) async {
        selectedAudioApp = app
        guard appState == .capturing else { return }
        guard #available(macOS 15.0, *) else { return }

        // Cancel old pipeline before the await so no overlap
        remotePipelineTask?.cancel()
        remotePipelineTask = nil
        remoteListening = false

        var newFilter: SCContentFilter? = nil
        if let app {
            if let content = try? await SCShareableContent.current,
               let scApp = content.applications.first(where: { $0.bundleIdentifier == app.bundleIdentifier }),
               let display = content.displays.first {
                newFilter = SCContentFilter(display: display, including: [scApp], exceptingWindows: [])
            }
        }

        // Re-check after suspension — session may have stopped during the await
        guard appState == .capturing else { return }

        do {
            let newStream = try await dualAudio.switchSystemFilter(newFilter)
            startRemotePipeline(stream: newStream)
        } catch {
            warningBadge = "Could not switch audio source"
        }
    }

    /// Called when the currently filtered app terminates. Falls back to all system audio.
    func handleFilteredAppTerminated(_ bundleID: String) async {
        guard selectedAudioApp?.bundleIdentifier == bundleID else { return }
        warningBadge = "'\(selectedAudioApp?.name ?? "App")' quit — switched to All System Audio"
        await switchAudioFilter(to: nil)
    }

    // MARK: - Private — Pipelines

    private func startMicPipeline(stream: AsyncStream<[Float]>) {
        micPipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await chunk in stream {
                guard !Task.isCancelled else { break }
                self.micListening = true
                do {
                    let result = try await self.transcriptionEngine.transcribe(
                        chunk, language: self.settingsStore.languageMode
                    )
                    guard !Task.isCancelled, !result.text.trimmingCharacters(in: .whitespaces).isEmpty else {
                        self.micListening = false
                        continue
                    }
                    self.transcriptStore.append(
                        TranscriptEntry(speaker: .you, timestamp: Date(), text: result.text)
                    )
                } catch {
                    self.warningBadge = "Mic transcription error"
                }
                self.micListening = false
            }
            if case .capturing = self.appState {
                self.warningBadge = "Mic disconnected"
            }
            self.micListening = false
        }
    }

    private func startRemotePipeline(stream: AsyncStream<[Float]>) {
        remotePipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await chunk in stream {
                guard !Task.isCancelled else { break }
                self.remoteListening = true
                do {
                    let result = try await self.transcriptionEngine.transcribe(
                        chunk, language: self.settingsStore.languageMode
                    )
                    guard !Task.isCancelled, !result.text.trimmingCharacters(in: .whitespaces).isEmpty else {
                        self.remoteListening = false
                        continue
                    }
                    self.transcriptStore.append(
                        TranscriptEntry(speaker: .remote, timestamp: Date(), text: result.text)
                    )
                } catch {
                    // Non-fatal — remote transcription errors do not stop the session
                }
                self.remoteListening = false
            }
            self.remoteListening = false
        }
    }

    private func startElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, case .capturing = self.appState else { break }
                self.elapsedSeconds += 1
            }
        }
    }

    private func cancelPipelines() {
        micPipelineTask?.cancel()
        remotePipelineTask?.cancel()
        elapsedTimerTask?.cancel()
        micPipelineTask = nil
        remotePipelineTask = nil
        elapsedTimerTask = nil
    }

    // MARK: - Startup Helpers

    /// Loads the persisted active model at startup.
    func loadActiveModel() async {
        let modelName = settingsStore.activeModelName
        guard !modelName.isEmpty else { return }
        do {
            try await transcriptionEngine.loadModel(modelName)
        } catch {
            await handleError("Failed to load model '\(modelName)' — open Model Management to fix")
        }
    }
}
