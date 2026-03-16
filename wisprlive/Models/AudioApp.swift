// wisprlive/Models/AudioApp.swift
import Foundation

/// Represents a running application that can be selected as an audio source.
struct AudioApp: Identifiable, Hashable, Sendable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}
