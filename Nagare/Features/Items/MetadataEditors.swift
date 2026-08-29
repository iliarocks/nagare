import SwiftUI

struct DraftScheduleEditor: View {
    @Binding var scheduledDate: Date
    @Binding var includesTime: Bool
    @Binding var startTime: Date
    @Binding var includesEndTime: Bool
    @Binding var endTime: Date

    var body: some View {
        ScheduleEditorForm(
            scheduledDate: $scheduledDate,
            includesTime: $includesTime,
            startTime: $startTime,
            includesEndTime: $includesEndTime,
            endTime: $endTime
        )
    }
}
