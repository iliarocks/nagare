import SwiftUI

struct EventRow: View {
    let event: Event
    let onOpen: () -> Void
    let onChangeSchedule: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(event.title)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                EventTimeLabel(
                    startDate: event.scheduledDate,
                    endDate: event.endDate
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .accessibilityAction(named: "Change Schedule", onChangeSchedule)
        .accessibilityAction(named: "Delete", onDelete)
    }
}

struct EventTimeLabel: View {
    let startDate: Date
    let endDate: Date?

    var body: some View {
        HStack(spacing: 4) {
            Text(startDate, format: .dateTime.hour().minute())

            if let endDate {
                Text("–")
                Text(endDate, format: .dateTime.hour().minute())
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
