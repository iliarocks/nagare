import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CalendarActivityView: UIViewControllerRepresentable {
    let file: SharedCalendarFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: [CalendarActivityItemSource(file: file)],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private final class CalendarActivityItemSource: NSObject,
    UIActivityItemSource {
    private let file: SharedCalendarFile

    init(file: SharedCalendarFile) {
        self.file = file
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        file.fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        file.fileURL
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        file.subject
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.calendarEvent.identifier
    }
}
