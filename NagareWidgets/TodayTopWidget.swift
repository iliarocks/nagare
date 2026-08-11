import AppIntents
import SwiftUI
import WidgetKit

struct TodayTopEntry: TimelineEntry {
    let date: Date
    let item: NagareWidgetItem?
}

struct TodayTopProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTopEntry {
        TodayTopEntry(
            date: .now,
            item: NagareWidgetItem(
                id: "preview",
                title: "Write what matters",
                kind: .todo,
                scheduledDate: .now,
                endDate: nil,
                order: "a"
            )
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (TodayTopEntry) -> Void
    ) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entry(at: .now))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<TodayTopEntry>) -> Void
    ) {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) ?? now.addingTimeInterval(60 * 60)

        completion(
            Timeline(
                entries: [entry(at: now)],
                policy: .after(tomorrow)
            )
        )
    }

    private func entry(at date: Date) -> TodayTopEntry {
        TodayTopEntry(
            date: date,
            item: NagareWidgetDataStore.read().topItem(
                on: date,
                calendar: .autoupdatingCurrent
            )
        )
    }
}

struct TodayTopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: NagareWidgetConstants.todayWidgetKind,
            provider: TodayTopProvider()
        ) { entry in
            TodayTopWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Top of Today")
        .description("Shows the first item in Today.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct TodayTopWidgetView: View {
    let entry: TodayTopEntry

    var body: some View {
        Button(intent: OpenNagareIntent(target: .today)) {
            ZStack {
                AccessoryWidgetBackground()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 12,
                            style: .continuous
                        )
                    )
                accessoryContent
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
            }
        }
        .buttonStyle(.plain)
    }

    private var accessoryContent: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("UP NEXT")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if let item = entry.item {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.kind == .event {
                    itemDetail(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing left")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func itemDetail(_ item: NagareWidgetItem) -> some View {
        switch item.kind {
        case .todo:
            Label("Next", systemImage: "circle")
        case .event:
            if let endDate = item.endDate {
                Text(
                    "\(item.scheduledDate.formatted(date: .omitted, time: .shortened))"
                        + "–\(endDate.formatted(date: .omitted, time: .shortened))"
                )
            } else {
                Text(
                    item.scheduledDate.formatted(
                        date: .omitted,
                        time: .shortened
                    )
                )
            }
        }
    }
}

#Preview("Lock Screen", as: .accessoryRectangular) {
    TodayTopWidget()
} timeline: {
    TodayTopEntry(
        date: .now,
        item: NagareWidgetItem(
            id: "preview",
            title: "Write what matters",
            kind: .todo,
            scheduledDate: .now,
            endDate: nil,
            order: "a"
        )
    )
}
