import SwiftUI

struct CompletedView: View {
    private struct CompletedGroup: Identifiable {
        let date: Date
        let todos: [TodoRecordSnapshot]

        var id: Date { date }
    }

    @NagareDataStoreEnvironment private var dataStore

    @State private var errorMessage: String?
    @State private var notesDestination: NotesDestination?
    @State private var notesDetent: PresentationDetent = .medium

    private var todos: [TodoRecordSnapshot] {
        dataStore.todos
    }

    private var groups: [CompletedGroup] {
        let calendar = Calendar.autoupdatingCurrent
        let completedTodos = todos.compactMap {
            todo -> (TodoRecordSnapshot, Date)? in
            guard let completedAt = todo.completedAt else {
                return nil
            }
            return (todo, completedAt)
        }
        let groupedTodos = Dictionary(grouping: completedTodos) {
            calendar.startOfDay(for: $0.1)
        }

        return groupedTodos.map { date, entries in
            CompletedGroup(
                date: date,
                todos: entries
                    .sorted { $0.1 > $1.1 }
                    .map(\.0)
            )
        }
        .sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No Completed Todos",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.todos) { todo in
                                completedRow(todo)
                            }
                            .nagareDesktopListRow()
                        } header: {
                            dateHeader(group.date)
                        }
                    }
                }
                .nagareListSectionSpacing(.custom(48))
                .contentMargins(.top, 24, for: .scrollContent)
            }
        }
        .sheet(
            item: $notesDestination,
            onDismiss: resetNotesSheet
        ) { destination in
            NotesSheet(
                destination: destination,
                detent: $notesDetent
            )
            .id(destination.id)
        }
        .alert("Nagare Couldn't Save", isPresented: isShowingError) {
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
            set: { isPresented in
                if !isPresented {
                    errorMessage = nil
                }
            }
        )
    }

    private func completedRow(_ todo: TodoRecordSnapshot) -> some View {
        Button {
            notesDetent = .medium
            notesDestination = .todo(todo.id)
        } label: {
            HStack(spacing: 12) {
                Text(todo.title)
                    .nagareItemTitleFont()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityLabel("\(todo.title), completed")
        .accessibilityAction(named: "Reinstate") {
            reinstate(todo)
        }
        .accessibilityAction(named: "Delete") {
            delete(todo)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                reinstate(todo)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .tint(.blue)
            .accessibilityLabel("Reinstate")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(todo)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete")
        }
        .nagareDesktopContextMenu {
            Button {
                reinstate(todo)
            } label: {
                Label("Reinstate", systemImage: "arrow.uturn.backward")
            }

            Divider()

            Button(role: .destructive) {
                delete(todo)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func dateHeader(_ date: Date) -> some View {
        HStack {
            Text(date, format: .dateTime.weekday(.wide))

            Spacer()

            Text(
                date,
                format: .dateTime.month(.wide).day()
            )
        }
        .font(.caption)
        .fontWeight(.regular)
    }

    private func reinstate(_ todo: TodoRecordSnapshot) {
        do {
            try withAnimation {
                try dataStore.reinstateTodo(todo.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ todo: TodoRecordSnapshot) {
        do {
            try withAnimation {
                try dataStore.deleteCompletedTodo(todo.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetNotesSheet() {
        notesDetent = .medium
    }
}
