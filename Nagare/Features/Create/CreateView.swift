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

    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var itemType = ItemType.todo
    @State private var title = ""
    @State private var notes = ""
    @State private var scheduledDate = Date.now
    @State private var startTime = Date.now
    @State private var includesEndTime = false
    @State private var endTime =
        Calendar.autoupdatingCurrent.date(
            byAdding: .hour,
            value: 1,
            to: .now
        ) ?? .now
    @State private var recurrence = RecurrenceFormState.disabled
    @State private var errorMessage: String?
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savedNotes: String? {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : notes
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

    private var recurrenceItemType: RecurrenceItemType {
        itemType == .todo ? .todo : .event
    }

    private var isFormValid: Bool {
        !trimmedTitle.isEmpty && isScheduleValid && recurrence.isValid
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $itemType) {
                    ForEach(ItemType.allCases) { type in
                        Text(type.title)
                            .tag(type)
                    }
                }
                .pickerStyle(.segmented)

                Section {
                    TextField(
                        itemType == .todo ? "What needs doing?" : "What's happening?",
                        text: $title
                    )
                    .accessibilityIdentifier("Create Title")
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTitleFocused = false
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityIdentifier("Create Notes")
                }

                Section {
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

                RecurrenceFields(
                    state: $recurrence,
                    itemType: recurrenceItemType,
                    referenceDate: itemType == .todo
                        ? scheduledDate
                        : eventScheduledDate
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New")
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
                    .disabled(!isFormValid)
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
            .onChange(of: itemType) {
                let referenceDate = itemType == .todo
                    ? scheduledDate
                    : eventScheduledDate
                recurrence.prepare(
                    for: recurrenceItemType,
                    referenceDate: referenceDate
                )
                recurrence.rebaseReference(to: referenceDate)
            }
            .onChange(of: scheduledDate) {
                guard itemType == .todo else {
                    return
                }
                recurrence.rebaseReference(to: scheduledDate)
            }
            .onChange(of: eventScheduledDate) {
                guard itemType == .event else {
                    return
                }
                recurrence.rebaseReference(to: eventScheduledDate)
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
        guard isFormValid else {
            errorMessage = "Complete the title, schedule, and repeat settings before saving. (CREATE-001)"
            return
        }

        do {
            let referenceDate = itemType == .todo
                ? scheduledDate
                : eventScheduledDate
            let rule = try recurrence.rule(referenceDate: referenceDate)

            switch itemType {
            case .todo:
                let order = try ItemOrdering.nextOrder(in: modelContext)
                let todo = Todo(
                    title: trimmedTitle,
                    notes: savedNotes,
                    scheduledDate: scheduledDate,
                    order: order
                )
                modelContext.insert(todo)
                if let rule {
                    _ = try RecurrencePersistence.createTemplate(
                        for: todo,
                        rule: rule,
                        in: modelContext
                    )
                } else {
                    try modelContext.save()
                }
            case .event:
                let order = try ItemOrdering.nextOrder(in: modelContext)
                let event = Event(
                    title: trimmedTitle,
                    notes: savedNotes,
                    scheduledDate: eventScheduledDate,
                    endDate: eventEndDate,
                    order: order
                )
                modelContext.insert(event)
                if let rule {
                    _ = try RecurrencePersistence.createTemplate(
                        for: event,
                        rule: rule,
                        in: modelContext
                    )
                } else {
                    try modelContext.save()
                }
            }

            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

}
