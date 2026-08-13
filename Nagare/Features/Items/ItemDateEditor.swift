import SwiftUI

struct ItemSelectionAction: Identifiable {
    let items: [ItemRecordSnapshot]

    var id: String {
        items.map(\.id.description).sorted().joined(separator: ",")
    }
}

/// Changes the calendar day of a persisted selection while preserving each
/// event's wall-clock time and duration. The data orchestrator commits the
/// whole selection in one ordering transaction.
struct ItemDateEditor: View {
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
            save()
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

    private func save() {
        guard !items.isEmpty else { return }
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.startOfDay(for: scheduledDate)
        guard items.contains(where: {
            !calendar.isDate($0.scheduledDate, inSameDayAs: day)
        }) else {
            return
        }

        do {
            try dataStore.moveItems(
                items.map(\.id),
                to: day,
                before: nil,
                calendar: calendar
            )
        } catch {
            scheduledDate = items.first?.scheduledDate ?? .now
            errorMessage = error.localizedDescription
        }
    }
}
