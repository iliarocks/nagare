import SwiftData
import SwiftUI

struct ItemFormView: View {
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
    @State private var endTime = Calendar.autoupdatingCurrent.date(
        byAdding: .hour,
        value: 1,
        to: .now
    ) ?? .now
    @State private var errorMessage: String?

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var eventStartDate: Date {
        date(on: scheduledDate, withTimeFrom: startTime)
    }

    private var eventEndDate: Date? {
        guard includesEndTime else {
            return nil
        }
        return date(on: scheduledDate, withTimeFrom: endTime)
    }

    private var isScheduleValid: Bool {
        guard let eventEndDate else {
            return true
        }
        return eventEndDate > eventStartDate
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
                    .submitLabel(.done)
                    .onSubmit(save)

                    DatePicker(
                        "Date",
                        selection: $scheduledDate,
                        in: Calendar.autoupdatingCurrent.startOfDay(for: .now)...,
                        displayedComponents: .date
                    )

                    if itemType == .event {
                        LabeledContent("Time") {
                            HStack(spacing: 8) {
                                DatePicker(
                                    "Start Time",
                                    selection: $startTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .labelsHidden()

                                if includesEndTime {
                                    Text("–")
                                        .foregroundStyle(.secondary)

                                    DatePicker(
                                        "End Time",
                                        selection: $endTime,
                                        displayedComponents: .hourAndMinute
                                    )
                                    .labelsHidden()
                                }

                                Button {
                                    includesEndTime.toggle()
                                } label: {
                                    Label(
                                        includesEndTime ? "Remove End Time" : "Add End Time",
                                        systemImage: includesEndTime ? "minus.circle.fill" : "plus.circle"
                                    )
                                    .labelStyle(.iconOnly)
                                }
                                .buttonStyle(.plain)
                            }
                        }
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
                let sortOrder = try ItemOrdering.nextSortOrder(
                    on: scheduledDate,
                    in: modelContext
                )
                modelContext.insert(
                    Todo(
                        title: trimmedTitle,
                        scheduledDate: scheduledDate,
                        sortOrder: sortOrder
                    )
                )
            case .event:
                let sortOrder = try ItemOrdering.nextSortOrder(
                    on: eventStartDate,
                    in: modelContext
                )
                modelContext.insert(
                    Event(
                        title: trimmedTitle,
                        startDate: eventStartDate,
                        endDate: eventEndDate,
                        sortOrder: sortOrder
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

    private func date(on day: Date, withTimeFrom time: Date) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: 0,
            of: day
        ) ?? day
    }
}
