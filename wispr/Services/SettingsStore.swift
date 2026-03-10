//
//  SettingsStore.swift
//  wispr
//
//  Settings persistence using UserDefaults
//

import Foundation
import Observation
import ServiceManagement
import os

@MainActor
@Observable
final class SettingsStore {
    // MARK: - Hotkey Settings
    var hotkeyKeyCode: UInt32 {
        didSet { save() }
    }
    
    var hotkeyModifiers: UInt32 {
        didSet { save() }
    }
    
    // MARK: - Audio Settings
    var selectedAudioDeviceUID: String? {
        didSet { save() }
    }
    
    // MARK: - Model Settings
    var activeModelName: String {
        didSet { save() }
    }
    
    // MARK: - Language Settings
    var languageMode: TranscriptionLanguage {
        didSet { save() }
    }
    
    // MARK: - General Settings
    var showRecordingOverlay: Bool {
        didSet { save() }
    }

    var launchAtLogin: Bool {
        didSet {
            save()
            guard !isLoading else { return }
            updateLaunchAtLogin(launchAtLogin)
        }
    }
    
    var onboardingCompleted: Bool {
        didSet { save() }
    }
    
    var onboardingLastStep: Int {
        didSet { save() }
    }
    
    // MARK: - Dictation Mode
    
    /// When true, hotkey toggles recording on/off (press once to start, press again to stop).
    /// When false, uses push-to-talk (hold to record, release to stop).
    var handsFreeMode: Bool {
        didSet { save() }
    }
    
    // MARK: - UserDefaults Keys
    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let activeModelName = "activeModelName"
        static let languageMode = "languageMode"
        static let showRecordingOverlay = "showRecordingOverlay"
        static let launchAtLogin = "launchAtLogin"
        static let onboardingCompleted = "onboardingCompleted"
        static let onboardingLastStep = "onboardingLastStep"
        static let handsFreeMode = "handsFreeMode"
    }
    
    // MARK: - Dependencies
    private let defaults: UserDefaults
    private var isLoading = false
    
    // MARK: - Initialization
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        // Initialize with defaults
        self.hotkeyKeyCode = 49  // Space
        self.hotkeyModifiers = 2048  // Option
        self.selectedAudioDeviceUID = nil
        self.activeModelName = ModelInfo.KnownID.tiny
        self.languageMode = .autoDetect
        self.showRecordingOverlay = true
        self.launchAtLogin = false
        self.onboardingCompleted = false
        self.onboardingLastStep = 0
        self.handsFreeMode = false
        
        // Load persisted values
        load()
    }
    
    // MARK: - Persistence
    func save() {
        // Don't save while loading to avoid overwriting persisted values
        guard !isLoading else { return }
        
        defaults.set(Int(hotkeyKeyCode), forKey: Keys.hotkeyKeyCode)
        defaults.set(Int(hotkeyModifiers), forKey: Keys.hotkeyModifiers)
        defaults.set(selectedAudioDeviceUID, forKey: Keys.selectedAudioDeviceUID)
        defaults.set(activeModelName, forKey: Keys.activeModelName)
        defaults.set(showRecordingOverlay, forKey: Keys.showRecordingOverlay)
        defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted)
        defaults.set(onboardingLastStep, forKey: Keys.onboardingLastStep)
        defaults.set(handsFreeMode, forKey: Keys.handsFreeMode)
        
        // Encode languageMode
        if let encoded = try? JSONEncoder().encode(languageMode) {
            defaults.set(encoded, forKey: Keys.languageMode)
        }
    }
    
    func load() {
        isLoading = true
        defer { isLoading = false }
        
        // Load hotkey settings
        let storedKeyCode = defaults.integer(forKey: Keys.hotkeyKeyCode)
        if storedKeyCode != 0 || defaults.object(forKey: Keys.hotkeyKeyCode) != nil {
            self.hotkeyKeyCode = UInt32(storedKeyCode)
        }
        
        let storedModifiers = defaults.integer(forKey: Keys.hotkeyModifiers)
        if storedModifiers != 0 || defaults.object(forKey: Keys.hotkeyModifiers) != nil {
            self.hotkeyModifiers = UInt32(storedModifiers)
        }
        
        // Load audio settings
        self.selectedAudioDeviceUID = defaults.string(forKey: Keys.selectedAudioDeviceUID)
        
        // Load model settings
        if let modelName = defaults.string(forKey: Keys.activeModelName) {
            self.activeModelName = modelName
        }
        
        // Load language mode
        if let data = defaults.data(forKey: Keys.languageMode),
           let decoded = try? JSONDecoder().decode(TranscriptionLanguage.self, from: data) {
            self.languageMode = decoded
        }
        
        // Load general settings
        if defaults.object(forKey: Keys.showRecordingOverlay) != nil {
            self.showRecordingOverlay = defaults.bool(forKey: Keys.showRecordingOverlay)
        }
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        
        self.onboardingLastStep = defaults.integer(forKey: Keys.onboardingLastStep)
        
        if defaults.object(forKey: Keys.handsFreeMode) != nil {
            self.handsFreeMode = defaults.bool(forKey: Keys.handsFreeMode)
        }
    }
    
    // MARK: - Launch at Login
    
    /// Registers or unregisters the app as a login item using ServiceManagement.
    /// After the operation, reads back the actual system state so the toggle
    /// always reflects reality.
    /// Requirements: 10.3, 10.4
    func updateLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                // unregister() throws if the app was never registered — that's
                // not a real failure, the desired state (not registered) is already true.
                if service.status != .notRegistered {
                    try service.unregister()
                }
            }
        } catch {
            Log.app.error("Failed to \(enabled ? "register" : "unregister") login item: \(error)")
        }
        
        // Always sync back to the actual system state
        let actualState = service.status == .enabled
        if launchAtLogin != actualState {
            isLoading = true
            launchAtLogin = actualState
            isLoading = false
            save()
        }
    }
}
