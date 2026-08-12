import SwiftUI

struct NagareSettingsView: View {
    @AppStorage(NagareCloudPreferences.syncEnabledKey)
    private var syncEnabled = false

#if os(macOS)
    @State private var isShowingCompleted = false
#endif

    let cloudSyncEnabledForCurrentLaunch: Bool

    private var restartRequired: Bool {
        syncEnabled != cloudSyncEnabledForCurrentLaunch
    }

    var body: some View {
#if os(macOS)
        Group {
            if isShowingCompleted {
                completedContent
            } else {
                settingsForm
            }
        }
        .frame(width: 480)
        .frame(minHeight: 430)
#else
        NavigationStack {
            settingsForm
        }
#endif
    }

    private var settingsForm: some View {
        Form {
            Section("History") {
#if os(macOS)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isShowingCompleted = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Label(
                            "Completed Items",
                            systemImage: "clock.arrow.circlepath"
                        )

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
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
    }

#if os(macOS)
    private var completedContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isShowingCompleted = false
                    }
                } label: {
                    Label(
                        "Back to Settings",
                        systemImage: "chevron.left"
                    )
                    .labelStyle(.iconOnly)
                }
                .nagareToolbarButton()
                .accessibilityIdentifier("Back to Settings")

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            CompletedView()
        }
        .onExitCommand {
            withAnimation(.snappy(duration: 0.2)) {
                isShowingCompleted = false
            }
        }
    }
#endif

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
