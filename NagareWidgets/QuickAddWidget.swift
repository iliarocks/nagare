import SwiftUI
import WidgetKit

private struct QuickAddEntry: TimelineEntry {
    let date: Date
}

private struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry {
        QuickAddEntry(date: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (QuickAddEntry) -> Void
    ) {
        completion(QuickAddEntry(date: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<QuickAddEntry>) -> Void
    ) {
        completion(
            Timeline(
                entries: [QuickAddEntry(date: .now)],
                policy: .never
            )
        )
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: NagareWidgetConstants.quickAddWidgetKind,
            provider: QuickAddProvider()
        ) { _ in
            QuickAddWidgetView()
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Quick Add")
        .description("Open Nagare to add a todo or event.")
        .supportedFamilies([.accessoryCircular])
        .contentMarginsDisabled()
    }
}

private struct QuickAddWidgetView: View {
    var body: some View {
        Link(destination: NagareDeepLink.quickAddURL) {
            ZStack {
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
            }
        }
    }
}

#Preview("Quick Add", as: .accessoryCircular) {
    QuickAddWidget()
} timeline: {
    QuickAddEntry(date: .now)
}
