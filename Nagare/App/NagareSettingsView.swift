import SwiftUI

struct NagareSettingsView: View {
    @AppStorage(NagareCloudPreferences.syncEnabledKey)
    private var syncEnabled = false

    let cloudSyncEnabledForCurrentLaunch: Bool

    private var restartRequired: Bool {
        syncEnabled != cloudSyncEnabledForCurrentLaunch
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("History") {
                    NavigationLink {
                        CompletedView()
                            .navigationTitle("Completed")
                    } label: {
                        Label(
                            "Completed Items",
                            systemImage: "clock.arrow.circlepath"
                        )
                    }
                }

                Section {
                    Toggle("Sync with iCloud", isOn: $syncEnabled)
                } header: {
                    Text("iCloud")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncExplanation)

                        if restartRequired {
                            Text("Relaunch Nagare to apply this change.")
                        }
                    }
                }

                Section("Data") {
                    comingSoonRow("Import Data", systemImage: "square.and.arrow.down")
                    comingSoonRow("Export Data", systemImage: "square.and.arrow.up")
                }

                Section("About") {
                    comingSoonRow("Privacy Policy", systemImage: "hand.raised")
                }
            }
            .formStyle(.grouped)
#if os(macOS)
            .frame(width: 480)
            .frame(minHeight: 430)
#endif
        }
    }

    private var syncExplanation: String {
        if syncEnabled {
            "Nagare syncs with your devices signed in to the same iCloud account."
        } else if cloudSyncEnabledForCurrentLaunch {
            "Sync continues until you relaunch Nagare. After that, new changes "
                + "stay only on this device and can be lost if it is damaged, "
                + "lost, or erased."
        } else {
            "Data is stored only on this device and can be lost if it is "
                + "damaged, lost, or erased."
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
