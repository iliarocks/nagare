import Foundation

/// Pure date movement rules for persisted items.
nonisolated enum ItemScheduleLogic {
    static func moving(
        _ item: ItemSnapshot,
        to destinationDate: Date,
        calendar: Calendar
    ) -> ItemOrderingChange {
        let destinationDay = calendar.startOfDay(for: destinationDate)
        guard item.includesTime else {
            return ItemOrderingChange(
                id: item.id,
                scheduledDate: destinationDay
            )
        }

        let duration = item.endDate.map {
            $0.timeIntervalSince(item.scheduledDate)
        }
        let time = calendar.dateComponents(
            [.hour, .minute, .second],
            from: item.scheduledDate
        )
        let start = calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: destinationDay
        ) ?? destinationDay
        return ItemOrderingChange(
            id: item.id,
            scheduledDate: start,
            endDate: duration.map(start.addingTimeInterval)
        )
    }
}
