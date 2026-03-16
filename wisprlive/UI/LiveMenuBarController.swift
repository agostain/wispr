//
//  LiveMenuBarController.swift
//  wisprlive
//
//  NSStatusItem-based menu bar for WisprLive.
//

import AppKit
import SwiftUI
import WisprKit

@MainActor
final class LiveMenuBarController {

    // MARK: - Properties

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let stateManager: LiveStateManager
    private let settingsStore: LiveSettingsStore
    private let transcriptStore: TranscriptStore
    private let transcriptWindowController: TranscriptWindowController
    private let transcriptionEngine: any TranscriptionEngine

    private var observationTask: Task<Void, Never>?

    private let captureMenuItem = NSMenuItem()
    private let transcriptMenuItem = NSMenuItem()
    private static let processingAnimationKey = "wisprlive.pulse"

    // MARK: - Init

    init(
        stateManager: LiveStateManager,
        settingsStore: LiveSettingsStore,
        transcriptStore: TranscriptStore,
        transcriptWindowController: TranscriptWindowController,
        transcriptionEngine: any TranscriptionEngine
    ) {
        self.stateManager = stateManager
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.transcriptWindowController = transcriptWindowController
        self.transcriptionEngine = transcriptionEngine
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        configureStatusButton()
        buildMenu()
        startObservingState()
    }

    // MARK: - Status Button

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "WisprLive")
        button.image?.isTemplate = true
        button.toolTip = "WisprLive — Conference Transcription"
        statusItem.menu = menu
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        menu.removeAllItems()
        updateCaptureMenuItem()
        menu.addItem(captureMenuItem)

        updateTranscriptMenuItem()
        menu.addItem(transcriptMenuItem)

        menu.addItem(NSMenuItem.separator())

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        languageItem.submenu = buildLanguageSubmenu()
        menu.addItem(languageItem)

        let modelItem = NSMenuItem(
            title: "Model Management…",
            action: #selector(LiveMenuBarActionHandler.openModelManagement(_:)),
            keyEquivalent: ""
        )
        menu.addItem(modelItem)

        let recentItem = NSMenuItem(title: "Recent Transcripts", action: nil, keyEquivalent: "")
        recentItem.submenu = buildRecentTranscriptsSubmenu()
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(LiveMenuBarActionHandler.openSettings(_:)),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit WisprLive",
            action: #selector(LiveMenuBarActionHandler.quitApp(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        let handler = LiveMenuBarActionHandler.shared
        handler.controller = self
        for item in menu.items where item.action != nil {
            item.target = handler
        }
    }

    private func updateCaptureMenuItem() {
        let isCapturing = stateManager.appState == .capturing
        captureMenuItem.title = isCapturing ? "Stop Transcription" : "Start Transcription"
        captureMenuItem.action = #selector(LiveMenuBarActionHandler.toggleCapture(_:))
        captureMenuItem.target = LiveMenuBarActionHandler.shared
        captureMenuItem.image = NSImage(
            systemSymbolName: isCapturing ? "stop.circle" : "waveform.circle",
            accessibilityDescription: nil
        )
    }

    private func updateTranscriptMenuItem() {
        transcriptMenuItem.title = "Show Transcript Window"
        transcriptMenuItem.action = #selector(LiveMenuBarActionHandler.showTranscript(_:))
        transcriptMenuItem.target = LiveMenuBarActionHandler.shared
    }

    private func buildRecentTranscriptsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let recents = transcriptStore.recentTranscriptURLs
        if recents.isEmpty {
            let none = NSMenuItem(title: "No Recent Transcripts", action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        } else {
            for url in recents {
                let item = NSMenuItem(
                    title: url.deletingPathExtension().lastPathComponent,
                    action: #selector(LiveMenuBarActionHandler.openRecentTranscript(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = url
                item.target = LiveMenuBarActionHandler.shared
                submenu.addItem(item)
            }
        }
        return submenu
    }

    private func buildLanguageSubmenu() -> NSMenu {
        let submenu = NSMenu()
        let autoItem = NSMenuItem(
            title: "Auto-Detect",
            action: #selector(LiveMenuBarActionHandler.selectAutoDetect(_:)),
            keyEquivalent: ""
        )
        autoItem.target = LiveMenuBarActionHandler.shared
        if settingsStore.languageMode.isAutoDetect { autoItem.state = .on }
        submenu.addItem(autoItem)
        submenu.addItem(NSMenuItem.separator())
        for lang in [("English", "en"), ("German", "de")] {
            let item = NSMenuItem(
                title: lang.0,
                action: #selector(LiveMenuBarActionHandler.selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = lang.1
            item.target = LiveMenuBarActionHandler.shared
            submenu.addItem(item)
        }
        return submenu
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        switch stateManager.appState {
        case .idle:
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "WisprLive Idle")
            button.image?.isTemplate = true
            stopPulse()
        case .capturing:
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "WisprLive Capturing")
            button.image?.isTemplate = false
            stopPulse()
        case .error:
            button.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: "WisprLive Error")
            button.image?.isTemplate = true
            stopPulse()
        }
    }

    private func startPulse() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0; pulse.toValue = 0.3; pulse.duration = 0.6
        pulse.autoreverses = true; pulse.repeatCount = .infinity
        button.layer?.add(pulse, forKey: Self.processingAnimationKey)
    }

    private func stopPulse() {
        statusItem.button?.layer?.removeAnimation(forKey: Self.processingAnimationKey)
    }

    // MARK: - State Observation

    private func startObservingState() {
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.updateIcon()
                self.updateCaptureMenuItem()
                await withCheckedContinuation { cont in
                    withObservationTracking {
                        _ = self.stateManager.appState
                    } onChange: { cont.resume() }
                }
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    // MARK: - Actions

    func toggleCapture() {
        Task {
            if stateManager.appState == .capturing {
                await stateManager.stopCapture()
            } else {
                await stateManager.startCapture()
            }
        }
    }

    func showTranscriptWindow() {
        transcriptWindowController.showWindow()
    }

    func selectAutoDetect() { settingsStore.languageMode = .autoDetect }

    func selectLanguage(_ code: String) { settingsStore.languageMode = .specific(code: code) }

    func openRecentTranscript(url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openModelManagement() {
        NSApp.activate()
        let activeModelBinding = Binding<String>(
            get: { [weak self] in self?.settingsStore.activeModelName ?? "" },
            set: { [weak self] newValue in self?.settingsStore.activeModelName = newValue }
        )
        let engine = transcriptionEngine
        let view = ModelManagementView(
            whisperService: engine,
            activeModelName: activeModelBinding,
            switchActiveModel: { modelName in
                try await engine.switchModel(to: modelName)
            }
        )
        let host = NSHostingController(rootView: view.environment(UIThemeEngine()))
        let win = NSWindow(contentViewController: host)
        win.title = "Model Management"
        win.styleMask = [.titled, .closable, .resizable]
        win.setContentSize(NSSize(width: 620, height: 640))
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    func openSettings() {
        NSApp.activate()
        let view = LiveSettingsView()
            .environment(settingsStore)
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "WisprLive Settings"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 480, height: 320))
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    func quitApp() {
        Task {
            if stateManager.appState == .capturing {
                await stateManager.stopCapture()
            }
        }
        stopObserving()
        NSApp.terminate(nil)
    }
}

// MARK: - Action Handler

final class LiveMenuBarActionHandler: NSObject {
    static let shared = LiveMenuBarActionHandler()
    weak var controller: LiveMenuBarController?

    @MainActor @objc func toggleCapture(_ sender: NSMenuItem) { controller?.toggleCapture() }
    @MainActor @objc func showTranscript(_ sender: NSMenuItem) { controller?.showTranscriptWindow() }
    @MainActor @objc func selectAutoDetect(_ sender: NSMenuItem) { controller?.selectAutoDetect() }
    @MainActor @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        controller?.selectLanguage(code)
    }
    @MainActor @objc func openRecentTranscript(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        controller?.openRecentTranscript(url: url)
    }
    @MainActor @objc func openModelManagement(_ sender: NSMenuItem) { controller?.openModelManagement() }
    @MainActor @objc func openSettings(_ sender: NSMenuItem) { controller?.openSettings() }
    @MainActor @objc func quitApp(_ sender: NSMenuItem) { controller?.quitApp() }
}
