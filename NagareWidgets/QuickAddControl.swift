import AppIntents
import SwiftUI
import WidgetKit

struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: NagareWidgetConstants.quickAddControlKind
        ) {
            ControlWidgetButton(
                action: OpenNagareIntent(target: .quickAdd)
            ) {
                Label("Quick Add", systemImage: "plus")
            }
        }
        .displayName("Quick Add")
        .description("Open Nagare to create a todo or event.")
    }
}
