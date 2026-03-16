//
//  DualAudioCapture.swift
//  wisprlive
//
//  Orchestrates two independent audio capture pipelines.
//  Returns separate chunk streams for mic (You) and system audio (Remote).
//

import Foundation
import ScreenCaptureKit

/// Coordinates MicAudioCapture and SystemAudioCapture.
///
/// On macOS < 15.0 the systemStream will be immediately finished (empty),
/// because ScreenCaptureKit audio capture requires macOS 15.0.
actor DualAudioCapture {

    private let micCapture: MicAudioCapture
    /// Stored as `Any?` to avoid `@available` on the stored property itself.
    /// Cast to `SystemAudioCapture` inside `stop()` with `#available`.
    private var systemCaptureHandle: Any?
    private(set) var isActive: Bool = false
    private(set) var micDisconnected: Bool = false

    let chunkDuration: TimeInterval

    init(chunkDuration: TimeInterval = 7.0) {
        self.chunkDuration = chunkDuration
        self.micCapture = MicAudioCapture(chunkDuration: chunkDuration)
    }

    // MARK: - Control

    struct AudioStreams {
        /// Chunks of 16kHz Float32 audio from the microphone ("You")
        let micStream: AsyncStream<[Float]>
        /// Chunks of 16kHz Float32 audio from system audio ("Remote")
        let systemStream: AsyncStream<[Float]>
    }

    /// Starts both audio pipelines.
    /// - Parameters:
    ///   - echoCancellation: Forward to MicAudioCapture (off by default).
    ///   - systemFilter: Optional `SCContentFilter` typed as `Any?` to avoid `@available`
    ///     constraint on the method signature. Cast to `SCContentFilter` inside `#available` guard.
    /// - Returns: Pair of async streams, one per speaker.
    func start(echoCancellation: Bool = false, systemFilter: Any? = nil) async throws -> AudioStreams {
        guard !isActive else { throw DualCaptureError.alreadyRunning }

        isActive = true
        micDisconnected = false

        // Start mic capture
        let micStream = try await micCapture.start(echoCancellation: echoCancellation)

        // Start system audio capture (macOS 15+)
        let systemStream: AsyncStream<[Float]>
        if #available(macOS 15.0, *) {
            let sysCapture = SystemAudioCapture(chunkDuration: chunkDuration)
            self.systemCaptureHandle = sysCapture  // retain so stop() can call stop()
            do {
                let filter = systemFilter as? SCContentFilter
                systemStream = try await sysCapture.start(filter: filter)
            } catch {
                // System audio failure is non-fatal — return empty stream
                self.systemCaptureHandle = nil
                let (empty, cont) = AsyncStream.makeStream(of: [Float].self)
                cont.finish()
                systemStream = empty
            }
        } else {
            let (empty, cont) = AsyncStream.makeStream(of: [Float].self)
            cont.finish()
            systemStream = empty
        }

        return AudioStreams(micStream: micStream, systemStream: systemStream)
    }

    /// Stops both pipelines and flushes remaining audio.
    func stop() async {
        guard isActive else { return }
        isActive = false
        await micCapture.stop()
        // Explicitly stop SystemAudioCapture — it does not self-stop on dealloc
        if #available(macOS 15.0, *), let sysCapture = systemCaptureHandle as? SystemAudioCapture {
            await sysCapture.stop()
        }
        systemCaptureHandle = nil
    }

    /// Called by LiveStateManager when mic disconnects mid-session.
    func handleMicDisconnect() {
        micDisconnected = true
    }

    /// Stops the current system audio capture and restarts it with a new filter.
    /// Returns the new stream. Only valid while a session is active.
    @available(macOS 15.0, *)
    func switchSystemFilter(_ filter: SCContentFilter?) async throws -> AsyncStream<[Float]> {
        guard isActive else { throw DualCaptureError.notRunning }
        if let old = systemCaptureHandle as? SystemAudioCapture {
            await old.stop()
        }
        systemCaptureHandle = nil
        let sysCapture = SystemAudioCapture(chunkDuration: chunkDuration)
        self.systemCaptureHandle = sysCapture
        do {
            return try await sysCapture.start(filter: filter)
        } catch {
            self.systemCaptureHandle = nil
            let (empty, cont) = AsyncStream.makeStream(of: [Float].self)
            cont.finish()
            return empty
        }
    }
}

// MARK: - Errors

enum DualCaptureError: LocalizedError {
    case alreadyRunning
    case notRunning

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "Audio capture is already running"
        case .notRunning: return "Audio capture is not running"
        }
    }
}
