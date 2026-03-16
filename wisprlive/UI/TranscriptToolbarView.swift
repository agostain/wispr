//
//  TranscriptToolbarView.swift
//  wisprlive
//
import SwiftUI
import WisprKit

/// Toolbar displayed at the top of the transcript window.
struct TranscriptToolbarView: View {

    @Environment(LiveStateManager.self) private var stateManager
    @Environment(LiveSettingsStore.self) private var settingsStore

    let onOpenSaveFolder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator
            if case .capturing = stateManager.appState {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.caption.weight(.medium))
                    Text(formattedElapsed)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("Stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let badge = stateManager.warningBadge {
                Label(badge, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Picker(
                selection: Binding(
                    get: { stateManager.selectedAudioApp?.id ?? "all" },
                    set: { id in
                        Task {
                            if id == "all" {
                                await stateManager.switchAudioFilter(to: nil)
                            } else if let app = stateManager.availableAudioApps.first(where: { $0.id == id }) {
                                await stateManager.switchAudioFilter(to: app)
                            }
                        }
                    }
                ),
                label: EmptyView()
            ) {
                Text("All System Audio").tag("all")
                if !stateManager.availableAudioApps.isEmpty {
                    Divider()
                    ForEach(stateManager.availableAudioApps) { app in
                        Text(app.name).tag(app.id)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.caption)
            .help("Audio source filter")
            .disabled(stateManager.appState != .capturing)
            .task(id: stateManager.appState) {
                if case .capturing = stateManager.appState {
                    await stateManager.fetchAudioApps()
                }
            }

            Button(action: onOpenSaveFolder) {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open transcripts folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var formattedElapsed: String {
        let s = Int(stateManager.elapsedSeconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
