import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct NagareSettingsView: View {
    private struct TransferNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

#if os(macOS)
    @Environment(\.openWindow) private var openWindow
#else
    @Environment(\.dismiss) private var dismiss
#endif
    @NagareDataStoreEnvironment private var dataStore

    @State private var syncEnabled: Bool
    @State private var isApplyingSyncPreference = false
    @State private var errorMessage: String?
    @State private var isShowingImporter = false
    @State private var isShowingExporter = false
    @State private var isShowingImportConfirmation = false
    @State private var isTransferringData = false
    @State private var exportDocument: NagareArchiveDocument?
    @State private var exportFilename = "Nagare Data"
    @State private var pendingImport: NagareDataImportPlan?
    @State private var transferNotice: TransferNotice?

    let onSetCloudSyncEnabled: (Bool) async throws -> Void

    init(
        onSetCloudSyncEnabled: @escaping (Bool) async throws -> Void = { _ in }
    ) {
        _syncEnabled = State(
            initialValue: NagareCloudPreferences.isSyncEnabled
        )
        self.onSetCloudSyncEnabled = onSetCloudSyncEnabled
    }

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
#if !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
#endif
        }
#if os(macOS)
        .frame(width: 480)
        .frame(minHeight: 430)
#endif
        .alert("iCloud Setting Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleImportSelection
        )
        .fileExporter(
            isPresented: $isShowingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename,
            onCompletion: handleExportCompletion
        )
        .alert(
            "Import Nagare Data?",
            isPresented: $isShowingImportConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                pendingImport = nil
            }
            Button("Import") {
                applyPendingImport()
            }
        } message: {
            Text(importConfirmationMessage)
        }
        .alert(item: $transferNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
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
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label(
                        "Completed Items",
                        systemImage: "clock.arrow.circlepath"
                    )
                }
#endif
            } header: {
                Text("History")
            }

            Section {
                Toggle(isOn: syncBinding) {
                    Label("Sync with iCloud", systemImage: "icloud")
                }
                    .disabled(isApplyingSyncPreference)
                Button {
                    beginImport()
                } label: {
                    dataTransferRow(
                        "Import Data",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTransferringData)

                Button(action: beginExport) {
                    dataTransferRow(
                        "Export Data",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTransferringData)
            } header: {
                Text("Data")
            }

            Section("About") {
                comingSoonRow("Privacy Policy", systemImage: "hand.raised")
                comingSoonRow("Support", systemImage: "lifepreserver")
            }
        }
        .formStyle(.grouped)
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
                transferNotice = TransferNotice(
                    title: "Restart Nagare",
                    message: "Close and reopen Nagare to finish changing iCloud sync."
                )
            } catch {
                syncEnabled = !isEnabled
                errorMessage = error.localizedDescription
            }
            isApplyingSyncPreference = false
        }
    }

    private var importConfirmationMessage: String {
        guard let summary = pendingImport?.summary else {
            return "The selected file is ready to import."
        }
        return "This file contains \(recordBreakdown(summary)). "
            + "Nagare will add \(summary.createdCount) and update "
            + "\(summary.updatedCount) matching records. Other data won't "
            + "be deleted."
    }

    private func beginImport() {
#if os(macOS)
        // SwiftUI's importer can disable valid JSON files when a macOS beta
        // assigns the extension an undeclared dynamic content type.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = true
        panel.prompt = "Import"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                handleImportSelection(.success([url]))
            }
        }
#else
        isShowingImporter = true
#endif
    }

    private func beginExport() {
        do {
            let date = Date.now
            exportDocument = NagareArchiveDocument(
                data: try dataStore.exportData(at: date)
            )
            exportFilename = "Nagare Data \(filenameDate(date))"
            isShowingExporter = true
        } catch {
            showTransferError("Export Failed", error: error)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw NagareDataArchiveError.invalidFile
            }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            pendingImport = try dataStore.prepareDataImport(data)
            isShowingImportConfirmation = true
        } catch {
            guard !isCancellation(error) else { return }
            showTransferError("Import Failed", error: error)
        }
    }

    private func applyPendingImport() {
        guard let plan = pendingImport else { return }
        pendingImport = nil
        isTransferringData = true
        Task {
            await Task.yield()
            defer { isTransferringData = false }
            do {
                try dataStore.importData(plan)
                let summary = plan.summary
                transferNotice = TransferNotice(
                    title: "Import Complete",
                    message: "Imported \(summary.totalCount) records: "
                        + "\(summary.createdCount) added and "
                        + "\(summary.updatedCount) updated."
                )
            } catch {
                showTransferError("Import Failed", error: error)
            }
        }
    }

    private func handleExportCompletion(_ result: Result<URL, Error>) {
        exportDocument = nil
        switch result {
        case .success:
            transferNotice = TransferNotice(
                title: "Export Complete",
                message: "Your Nagare data file was saved successfully."
            )
        case .failure(let error) where !isCancellation(error):
            showTransferError("Export Failed", error: error)
        case .failure:
            break
        }
    }

    private func showTransferError(_ title: String, error: Error) {
        transferNotice = TransferNotice(
            title: title,
            message: error.localizedDescription
        )
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as NSError).code == CocoaError.Code.userCancelled.rawValue
    }

    private func filenameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func recordBreakdown(_ summary: NagareDataImportSummary) -> String {
        [
            count(summary.projectCount, singular: "project"),
            count(summary.todoCount, singular: "todo"),
            count(summary.recurrenceCount, singular: "repeat")
        ].joined(separator: ", ")
    }

    private func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }

    private func dataTransferRow(
        _ title: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer()
            if isTransferringData {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
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
