import SwiftUI

struct NagareSettingsView: View {
    @AppStorage(NagareCloudPreferences.syncEnabledKey)
    private var syncEnabled = false
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#endif

    let cloudSyncEnabledForCurrentLaunch: Bool

    private var restartRequired: Bool {
        syncEnabled != cloudSyncEnabledForCurrentLaunch
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
                Toggle("Sync with iCloud", isOn: $syncEnabled)
            } header: {
                Text("iCloud")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(syncExplanation)

                    if restartRequired {
                        Text("Relaunch Nagare to apply this change")
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
    }

    private var syncExplanation: String {
        if syncEnabled {
            "Nagare syncs with devices signed in to the same iCloud account"
        } else if cloudSyncEnabledForCurrentLaunch {
            "Sync continues until you relaunch Nagare. After that, new changes "
                + "stay only on this device and can be lost if it is damaged, "
                + "lost, or erased"
        } else {
            "Data is stored only on this device and can be lost if it is "
                + "damaged, lost, or erased"
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
