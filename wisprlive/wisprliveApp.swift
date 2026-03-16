//
//  wisprliveApp.swift
//  wisprlive
//
//  Main entry point. Bootstraps all services and presents the menu bar.
//

import SwiftUI
import WisprKit

@main
struct WisprLiveApp: App {
    @NSApplicationDelegateAdaptor(WisprLiveAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }

    init() {
        guard ProcessInfo.processInfo.environment["CI_TEST_MODE"] == nil else { return }
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

@MainActor
final class WisprLiveAppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    let settingsStore = LiveSettingsStore()
    let transcriptStore: TranscriptStore
    let transcriptionEngine: any TranscriptionEngine = CompositeTranscriptionEngine(engines: [
        WhisperService(),
        ParakeetService()
    ])
    let hotkeyMonitor = HotkeyMonitor()
    let dualAudio = DualAudioCapture()

    private(set) var stateManager: LiveStateManager?
    private var menuBarController: LiveMenuBarController?
    private var transcriptWindowController: TranscriptWindowController?
    private var hotkeyObservationTask: Task<Void, Never>?
    private var onboardingWindow: NSWindow?
    private var appTerminationObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    override init() {
        self.transcriptStore = TranscriptStore(
            saveDirectory: LiveSettingsStore().saveDirectory
        )
        super.init()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["CI_TEST_MODE"] == nil else { return }
        bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = appTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        hotkeyObservationTask?.cancel()
        Task {
            if let sm = stateManager, sm.appState == .capturing {
                await sm.stopCapture()
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        let sm = LiveStateManager(
            transcriptionEngine: transcriptionEngine,
            transcriptStore: transcriptStore,
            settingsStore: settingsStore,
            dualAudio: dualAudio
        )
        self.stateManager = sm

        let windowController = TranscriptWindowController(
            stateManager: sm,
            transcriptStore: transcriptStore,
            settingsStore: settingsStore
        )
        self.transcriptWindowController = windowController

        menuBarController = LiveMenuBarController(
            stateManager: sm,
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            transcriptWindowController: windowController,
            transcriptionEngine: transcriptionEngine
        )

        // Register default hotkey
        try? hotkeyMonitor.register(
            keyCode: settingsStore.hotkeyKeyCode,
            modifiers: settingsStore.hotkeyModifiers
        )

        // Wire hotkey to toggle capture
        hotkeyMonitor.onHotkeyDown = { [weak sm] in
            Task { @MainActor in
                guard let sm else { return }
                if sm.appState == .capturing {
                    await sm.stopCapture()
                } else {
                    await sm.startCapture()
                }
            }
        }

        startHotkeyObservation()

        if !settingsStore.onboardingCompleted {
            showOnboarding(stateManager: sm)
        } else {
            Task { await sm.loadActiveModel() }
        }

        // Observe app termination to fall back from per-app audio filter
        appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier else { return }
            Task { @MainActor in
                await self?.stateManager?.handleFilteredAppTerminated(bundleID)
            }
        }

        // Stop capture when Mac goes to sleep; user can restart on wake
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let sm = self?.stateManager, sm.appState == .capturing else { return }
                await sm.stopCapture()
            }
        }
    }

    private func startHotkeyObservation() {
        hotkeyObservationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await withCheckedContinuation { cont in
                    withObservationTracking {
                        _ = self.settingsStore.hotkeyKeyCode
                        _ = self.settingsStore.hotkeyModifiers
                    } onChange: { cont.resume() }
                }
                guard !Task.isCancelled else { return }
                try? self.hotkeyMonitor.updateHotkey(
                    keyCode: self.settingsStore.hotkeyKeyCode,
                    modifiers: self.settingsStore.hotkeyModifiers
                )
            }
        }
    }

    private func showOnboarding(stateManager: LiveStateManager) {
        let view = LiveOnboardingFlow(
            transcriptionEngine: transcriptionEngine,
            settingsStore: settingsStore,
            onDismiss: { [weak self] in self?.completeOnboarding() }
        )
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "WisprLive Setup"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 600, height: 500))
        win.center()
        win.level = .floating
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        self.onboardingWindow = win
    }

    private func completeOnboarding() {
        settingsStore.onboardingCompleted = true
        onboardingWindow?.close()
        onboardingWindow = nil
        if let sm = stateManager {
            Task { await sm.loadActiveModel() }
        }
    }
}
