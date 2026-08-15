import SwiftUI

struct NagareSettingsView: View {
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    @State private var syncEnabled: Bool
    @State private var isApplyingSyncPreference = false
    @State private var lastSyncRequest: Date?
    @State private var errorMessage: String?

    let onSetCloudSyncEnabled: (Bool) async throws -> Void
    let onSyncNow: () -> Void

    init(
        cloudSyncEnabledForCurrentLaunch: Bool,
        onSetCloudSyncEnabled: @escaping (Bool) async throws -> Void = { _ in },
        onSyncNow: @escaping () -> Void = {}
    ) {
        _syncEnabled = State(
            initialValue: cloudSyncEnabledForCurrentLaunch
        )
        self.onSetCloudSyncEnabled = onSetCloudSyncEnabled
        self.onSyncNow = onSyncNow
    }

    var body: some View {
        NavigationStack {
            settingsForm
        }
#if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 430)
        .navigationTitle("Settings")
#endif
        .alert("iCloud Setting Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
#if os(macOS)
                Button {
                    openWindow(id: NagareWindowID.completed)
                } label: {
                    HStack(spacing: 12) {
                        Label(
                            "Completed Items",
                            systemImage: "clock.arrow.circlepath"
                        )

                        Spacer()

                        Image(systemName: "arrow.up.forward.app")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
#else
                NavigationLink {
                    CompletedView()
                        .navigationTitle("Completed")
                } label: {
                    Label(
                        "Completed Items",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
#endif
            } header: {
                Text("History")
            } footer: {
                Text("Review, restore, or permanently delete completed todos")
            }

            Section {
                Toggle("Sync with iCloud", isOn: syncBinding)
                    .disabled(isApplyingSyncPreference)

                if syncEnabled {
                    Button {
                        onSyncNow()
                        lastSyncRequest = .now
                    } label: {
                        HStack(spacing: 12) {
                            Label(
                                "Sync Now",
                                systemImage: "arrow.triangle.2.circlepath"
                            )

                            Spacer()

                            if let lastSyncRequest {
                                Text(
                                    lastSyncRequest,
                                    format: .dateTime.hour().minute()
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplyingSyncPreference)
                }
            } header: {
                Text("iCloud")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncExplanation)

                    if isApplyingSyncPreference {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Applying…")
                        }
                    } else if syncEnabled {
                        Text(
                            "Sync Now incorporates changes already delivered "
                                + "to this device; iCloud controls network delivery"
                        )
                    }
                }
            }

            Section("Data") {
                comingSoonRow("Import Data", systemImage: "square.and.arrow.down")
                comingSoonRow("Export Data", systemImage: "square.and.arrow.up")
            }

            Section("About") {
                comingSoonRow("Privacy Policy", systemImage: "hand.raised")
                comingSoonRow("Support", systemImage: "lifepreserver")
            }
        }
        .formStyle(.grouped)
#if !os(macOS)
        .contentMargins(.top, 24, for: .scrollContent)
#endif
    }

    private var syncExplanation: String {
        if syncEnabled {
            "Nagare syncs with devices signed in to the same iCloud account"
        } else {
            "Data is stored only on this device and can be lost if it is "
                + "damaged, lost, or erased"
        }
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { syncEnabled },
            set: applySyncPreference
        )
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func applySyncPreference(_ isEnabled: Bool) {
        guard isEnabled != syncEnabled,
              !isApplyingSyncPreference else {
            return
        }
        syncEnabled = isEnabled
        isApplyingSyncPreference = true

        Task {
            await Task.yield()
            do {
                try await onSetCloudSyncEnabled(isEnabled)
            } catch {
                syncEnabled = !isEnabled
                errorMessage = error.localizedDescription
            }
            isApplyingSyncPreference = false
        }
    }

    private func comingSoonRow(
        _ title: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text("Coming Soon")
                .foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityElement(children: .combine)
    }

}
