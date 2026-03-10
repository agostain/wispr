//
//  TranscriptionResult.swift
//  wispr
//
//  Created by Kiro
//

import Foundation

/// Result of a transcription operation
struct TranscriptionResult: Sendable, Equatable {
    let text: String
    let detectedLanguage: String?
    let duration: TimeInterval
    /// True when the transcription engine detected end-of-utterance.
    /// Used by StateManager to auto-stop recording in hands-free mode.
    let isEndOfUtterance: Bool

    nonisolated init(text: String, detectedLanguage: String? = nil, duration: TimeInterval, isEndOfUtterance: Bool = false) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.duration = duration
        self.isEndOfUtterance = isEndOfUtterance
    }
}
