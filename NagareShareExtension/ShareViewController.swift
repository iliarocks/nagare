import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<CalendarShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let model = CalendarShareModel(extensionContext: extensionContext)
        let hostingController = UIHostingController(
            rootView: CalendarShareView(model: model)
        )
        self.hostingController = hostingController

        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(
                equalTo: view.bottomAnchor
            )
        ])
        hostingController.didMove(toParent: self)

        Task {
            await model.load(
                inputItems: extensionContext?.inputItems ?? []
            )
        }
    }
}

@MainActor
private final class CalendarShareModel: ObservableObject {
    enum State {
        case loading
        case ready(ICalendarEventDraft)
        case saving(ICalendarEventDraft)
        case failed(String)
    }

    @Published private(set) var state = State.loading

    private let extensionContext: NSExtensionContext?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func load(inputItems: [Any]) async {
        do {
            let provider = try calendarProvider(in: inputItems)
            let identifier = try calendarTypeIdentifier(for: provider)
            let data = try await data(
                from: provider,
                typeIdentifier: identifier
            )
            guard data.count <= 5_000_000 else {
                throw ShareImportError.fileTooLarge
            }
            state = .ready(
                try ICalendarParser.parse(
                    data,
                    defaultTimeZone: .autoupdatingCurrent
                )
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func add(_ draft: ICalendarEventDraft) {
        state = .saving(draft)
        do {
            try PendingCalendarImportStore.enqueue(draft)
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: NSCocoaErrorDomain,
                code: NSUserCancelledError
            )
        )
    }

    private func calendarProvider(in inputItems: [Any]) throws -> NSItemProvider {
        let providers = inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(
                UTType.calendarEvent.identifier
            )
        }) else {
            throw ShareImportError.missingCalendarFile
        }
        return provider
    }

    private func calendarTypeIdentifier(
        for provider: NSItemProvider
    ) throws -> String {
        if let identifier = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .calendarEvent) == true
        }) {
            return identifier
        }
        if provider.hasItemConformingToTypeIdentifier(
            UTType.calendarEvent.identifier
        ) {
            return UTType.calendarEvent.identifier
        }
        throw ShareImportError.missingCalendarFile
    }

    private func data(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(
                        throwing: error ?? ShareImportError.unreadableAttachment
                    )
                }
            }
        }
    }
}

private struct CalendarShareView: View {
    @ObservedObject var model: CalendarShareModel

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Reading Invite…")
                case .ready(let draft):
                    eventPreview(draft, isSaving: false)
                case .saving(let draft):
                    eventPreview(draft, isSaving: true)
                case .failed(let message):
                    ContentUnavailableView {
                        Label(
                            "Invite Couldn't Be Read",
                            systemImage: "exclamationmark.triangle"
                        )
                    } description: {
                        Text(message)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Add to Nagare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.cancel)
                }
            }
        }
    }

    private func eventPreview(
        _ draft: ICalendarEventDraft,
        isSaving: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Calendar Event", systemImage: "calendar.badge.plus")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(draft.title.isEmpty ? "Untitled Event" : draft.title)
                .font(.title2.weight(.semibold))

            Text(schedule(for: draft))
                .foregroundStyle(.secondary)

            if let notes = draft.notes {
                Text(notes)
                    .lineLimit(4)
            }

            Spacer()

            Button {
                model.add(draft)
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Add to Nagare")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding(24)
    }

    private func schedule(for draft: ICalendarEventDraft) -> String {
        if draft.isAllDay {
            return draft.scheduledDate.formatted(
                date: .complete,
                time: .omitted
            )
        }
        let start = draft.scheduledDate.formatted(
            date: .complete,
            time: .shortened
        )
        guard let endDate = draft.endDate else { return start }
        return "\(start)–\(endDate.formatted(date: .omitted, time: .shortened))"
    }
}

private enum ShareImportError: LocalizedError {
    case missingCalendarFile
    case unreadableAttachment
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .missingCalendarFile:
            "Share a single .ics calendar file with Nagare."
        case .unreadableAttachment:
            "The app sharing this invite didn't provide readable calendar data."
        case .fileTooLarge:
            "This calendar file is too large to import."
        }
    }
}
