import SwiftUI

struct ItemRow: View {
    let item: Item
    let onOpen: (Item) -> Void
    let onComplete: (Todo) -> Void
    let onChangeSchedule: (Item) -> Void
    let onMoveProject: (Item) -> Void
    let onDelete: (Item) -> Void

    @State private var sharedCalendarFile: SharedCalendarFile?
    @State private var sharingErrorMessage: String?

    var body: some View {
        ZStack {
            switch item {
            case .todo(let todo):
                TodoRow(
                    todo: todo,
                    onOpen: { onOpen(item) },
                    onComplete: { onComplete(todo) },
                    onChangeDate: { onChangeSchedule(item) },
                    onMoveProject: { onMoveProject(item) },
                    onDelete: { onDelete(item) }
                )
            case .event(let event):
                EventRow(
                    event: event,
                    onOpen: { onOpen(item) },
                    onChangeSchedule: { onChangeSchedule(item) },
                    onMoveProject: { onMoveProject(item) },
                    onDelete: { onDelete(item) }
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onChangeSchedule(item)
            } label: {
                Image(systemName: scheduleActionIcon)
            }
            .tint(.blue)
            .accessibilityLabel(scheduleActionTitle)

            Button {
                onMoveProject(item)
            } label: {
                Image(systemName: "folder")
            }
            .tint(.indigo)
            .accessibilityLabel("Move Project")

            if case .event(let event) = item {
                Button {
                    share(event)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(.green)
                .accessibilityLabel("Share Event")
            }
        }
        .nagareDesktopContextMenu {
            if case .todo(let todo) = item {
                Button {
                    onComplete(todo)
                } label: {
                    Label("Complete", systemImage: "checkmark.circle")
                }

                Divider()
            }

            Button {
                onChangeSchedule(item)
            } label: {
                Label(scheduleActionTitle, systemImage: scheduleActionIcon)
            }

            Button {
                onMoveProject(item)
            } label: {
                Label("Move Project", systemImage: "folder")
            }

            if case .event(let event) = item {
                Button {
                    share(event)
                } label: {
                    Label("Share Event", systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button(role: .destructive) {
                onDelete(item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(item: $sharedCalendarFile) { file in
            CalendarActivityView(file: file)
                .ignoresSafeArea()
        }
        .alert(
            "Event Couldn't Be Shared",
            isPresented: isShowingSharingError
        ) {
            Button("OK", role: .cancel) {
                sharingErrorMessage = nil
            }
        } message: {
            Text(sharingErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var scheduleActionTitle: String {
        switch item {
        case .todo: "Change Date"
        case .event: "Change Date and Time"
        }
    }

    private var scheduleActionIcon: String {
        switch item {
        case .todo: "calendar"
        case .event: "calendar.badge.clock"
        }
    }

    private var isShowingSharingError: Binding<Bool> {
        Binding(
            get: { sharingErrorMessage != nil },
            set: { if !$0 { sharingErrorMessage = nil } }
        )
    }

    private func share(_ event: Event) {
        do {
            sharedCalendarFile = try ICalendarExportStore.write(
                ICalendarExportFile(event: event)
            )
        } catch {
            sharingErrorMessage = error.localizedDescription
        }
    }
}
