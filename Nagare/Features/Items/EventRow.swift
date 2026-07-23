import SwiftUI

struct EventRow: View {
    let event: Event
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(event.title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    Text(event.scheduledDate, format: .dateTime.hour().minute())

                    if let endDate = event.endDate {
                        Text("–")
                        Text(endDate, format: .dateTime.hour().minute())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
