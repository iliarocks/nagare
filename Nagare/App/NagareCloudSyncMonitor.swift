import CoreData
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class NagareCloudSyncMonitor {
    enum Phase: Equatable {
        case disabled
        case connecting
        case syncing
        case upToDate
        case failed
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nagare",
        category: "CloudSync"
    )

    private var transportPhase: Phase
    private(set) var lastSuccessfulImport: Date?
    private(set) var lastSuccessfulExport: Date?
    private(set) var lastErrorDate: Date?
    private var cloudErrorDescription: String?
    private var historyObservationError: String?

    @ObservationIgnored
    private var observationToken: NotificationCenter.ObservationToken?
    @ObservationIgnored
    private var activeEvents: [UUID: NSPersistentCloudKitContainer.EventType] = [:]
    @ObservationIgnored
    private var onSuccessfulImport: () -> Void = {}

    init(isEnabled: Bool) {
        transportPhase = isEnabled ? .connecting : .disabled
        guard isEnabled else { return }
        observationToken = NotificationCenter.default.addObserver(
            of: NSPersistentCloudKitContainer.self,
            for: .eventChanged
        ) { [weak self] message in
            Task { @MainActor [weak self] in
                self?.record(message.event)
            }
        }
    }

    deinit {
        if let observationToken {
            NotificationCenter.default.removeObserver(observationToken)
        }
    }

    var phase: Phase {
        lastErrorDescription == nil ? transportPhase : .failed
    }

    var lastErrorDescription: String? {
        historyObservationError ?? cloudErrorDescription
    }

    func stop() {
        if let observationToken {
            NotificationCenter.default.removeObserver(observationToken)
        }
        observationToken = nil
        activeEvents.removeAll()
        onSuccessfulImport = {}
    }

    func setOnSuccessfulImport(_ action: @escaping () -> Void) {
        onSuccessfulImport = action
    }

    func recordHistoryObservation(
        isHealthy: Bool,
        errorDescription: String? = nil
    ) {
        guard transportPhase != .disabled else { return }
        if isHealthy {
            historyObservationError = nil
        } else {
            historyObservationError = errorDescription
                ?? "Nagare couldn't observe synchronized changes."
        }
    }

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        record(
            type: event.type,
            identifier: event.identifier as UUID,
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded,
            errorDescription: event.error?.localizedDescription
        )
    }

    func record(
        type: NSPersistentCloudKitContainer.EventType,
        identifier: UUID,
        startDate: Date,
        endDate: Date?,
        succeeded: Bool,
        errorDescription: String?
    ) {
        guard transportPhase != .disabled else { return }

        guard let endDate else {
            activeEvents[identifier] = type
            transportPhase = .syncing
            return
        }

        activeEvents.removeValue(forKey: identifier)
        if succeeded {
            switch type {
            case .import:
                lastSuccessfulImport = endDate
                onSuccessfulImport()
            case .export:
                lastSuccessfulExport = endDate
            case .setup:
                break
            @unknown default:
                break
            }
            if lastErrorDate.map({ $0 <= startDate }) != false {
                cloudErrorDescription = nil
                lastErrorDate = nil
            }
            transportPhase = activeEvents.isEmpty ? .upToDate : .syncing
        } else {
            cloudErrorDescription = errorDescription
                ?? "iCloud couldn't complete this sync operation."
            lastErrorDate = endDate
            Self.logger.error(
                "CloudKit \(String(describing: type), privacy: .public) failed: \(self.lastErrorDescription ?? "Unknown error", privacy: .public)"
            )
        }
    }
}
