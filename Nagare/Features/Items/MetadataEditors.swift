import SwiftUI

struct DraftScheduleEditor: View {
    @Binding var scheduledDate: Date
    @Binding var includesTime: Bool
    @Binding var startTime: Date
    @Binding var includesEndTime: Bool
    @Binding var endTime: Date

    private var resolvedScheduledDate: Date {
        if includesTime {
            return ScheduleDateTime.combining(scheduledDate, with: startTime)
        }
        return Calendar.autoupdatingCurrent.startOfDay(for: scheduledDate)
    }

    private var resolvedEndDate: Date? {
        guard includesTime && includesEndTime else { return nil }
        return ScheduleDateTime.combining(scheduledDate, with: endTime)
    }

    private var isScheduleValid: Bool {
        guard let resolvedEndDate else { return true }
        return resolvedEndDate > resolvedScheduledDate
    }

    var body: some View {
        ScheduleEditorForm(
            scheduledDate: $scheduledDate,
            includesTime: $includesTime,
            startTime: $startTime,
            includesEndTime: $includesEndTime,
            endTime: $endTime,
            isScheduleValid: isScheduleValid
        )
    }
}
