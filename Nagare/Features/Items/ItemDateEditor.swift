import SwiftUI

struct ItemSelectionAction: Identifiable {
    let items: [ItemRecordSnapshot]

    var id: String {
        items.map(\.id.description).sorted().joined(separator: ",")
    }
}

/// Changes the calendar day of a persisted selection while preserving each
/// timed Todo's wall-clock time and duration. The data orchestrator commits the
/// whole selection in one ordering transaction.
struct ItemDateEditor: View {
    @Environment(\.nagareDismissModal) private var dismiss
    @NagareDataStoreEnvironment private var dataStore

    let items: [ItemRecordSnapshot]

    @State private var scheduledDate: Date
    @State private var errorMessage: String?

    init(items: [ItemRecordSnapshot]) {
        self.items = items
        _scheduledDate = State(
            initialValue: items.first?.scheduledDate ?? .now
        )
    }

    var body: some View {
        DatePicker(
            "Date",
            selection: $scheduledDate,
            in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
#if os(macOS)
        .controlSize(.regular)
        .focusEffectDisabled()
        .fixedSize()
        .padding(16)
#endif
        .onChange(of: scheduledDate) {
            if save() {
                dismiss()
            }
        }
        .alert("Details Couldn't Be Changed", isPresented: isShowingError) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @discardableResult
    private func save() -> Bool {
        guard !items.isEmpty else { return false }
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: scheduledDate)
        guard items.contains(where: {
            !calendar.isDate($0.scheduledDate, inSameDayAs: day)
        }) else {
            return false
        }

        do {
            try dataStore.moveItems(
                items.map(\.id),
                to: day,
                before: nil,
                calendar: calendar
            )
            return true
        } catch {
            scheduledDate = items.first?.scheduledDate ?? .now
            errorMessage = error.localizedDescription
            return false
        }
    }
}
