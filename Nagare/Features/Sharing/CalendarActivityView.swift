import SwiftUI
#if canImport(UIKit)
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
#elseif canImport(AppKit)
import AppKit

struct CalendarActivityView: NSViewRepresentable {
    let file: SharedCalendarFile

    func makeNSView(context: Context) -> NSView {
        SharingPickerView(file: file)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class SharingPickerView: NSView {
    private let file: SharedCalendarFile
    private var hasPresentedPicker = false

    init(file: SharedCalendarFile) {
        self.file = file
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !hasPresentedPicker else { return }
        hasPresentedPicker = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSSharingServicePicker(items: [file.fileURL]).show(
                relativeTo: bounds,
                of: self,
                preferredEdge: .minY
            )
        }
    }
}
#endif
