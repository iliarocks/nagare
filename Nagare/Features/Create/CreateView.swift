import SwiftData
import SwiftUI

struct CreateView: View {
    private enum ItemType: String, CaseIterable, Identifiable {
        case todo
        case event

        var id: Self { self }

        var title: String {
            switch self {
            case .todo: "Todo"
            case .event: "Event"
            }
        }

        var icon: String {
            switch self {
            case .todo: "checkmark.circle"
            case .event: "clock"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var itemType = ItemType.todo
    @State private var title = ""
    @State private var scheduledDate = Date.now
    @State private var startTime = Date.now
    @State private var includesEndTime = false
    @State private var endTime =
        Calendar.autoupdatingCurrent.date(
            byAdding: .hour,
            value: 1,
            to: .now
        ) ?? .now
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eventScheduledDate: Date {
        ScheduleDateTime.combining(scheduledDate, with: startTime)
    }

    private var eventEndDate: Date? {
        guard includesEndTime else {
            return nil
        }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    private var isScheduleValid: Bool {
        guard let eventEndDate else {
            return true
        }
        return eventEndDate > eventScheduledDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $itemType) {
                    ForEach(ItemType.allCases) { type in
                        Label(type.title, systemImage: type.icon)
                            .labelStyle(.iconOnly)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField(
                        itemType == .todo ? "What needs doing?" : "What's happening?",
                        text: $title
                    )
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit(save)

                    if itemType == .event {
                        ScheduleFields(
                            date: $scheduledDate,
                            startTime: $startTime,
                            includesEndTime: $includesEndTime,
                            endTime: $endTime
                        )
                    } else {
                        DatePicker(
                            "Date",
                            selection: $scheduledDate,
                            in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                            displayedComponents: .date
                        )
                    }
                } footer: {
                    if itemType == .event && !isScheduleValid {
                        Text("The end time must be later than the start time.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New \(itemType.title)")
                        .font(.headline)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Label("Add \(itemType.title)", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .tint(.accentColor)
                    .disabled(trimmedTitle.isEmpty || !isScheduleValid)
                }
            }
            .alert("\(itemType.title) Couldn't Be Created", isPresented: isShowingError) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .task {
                isTitleFocused = true
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func save() {
        guard !trimmedTitle.isEmpty && isScheduleValid else {
            return
        }

        do {
            switch itemType {
            case .todo:
                let order = try ItemOrdering.nextOrder(in: modelContext)
                modelContext.insert(
                    Todo(
                        title: trimmedTitle,
                        scheduledDate: scheduledDate,
                        order: order
                    )
                )
            case .event:
                let order = try ItemOrdering.nextOrder(in: modelContext)
                modelContext.insert(
                    Event(
                        title: trimmedTitle,
                        scheduledDate: eventScheduledDate,
                        endDate: eventEndDate,
                        order: order
                    )
                )
            }

            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

}
