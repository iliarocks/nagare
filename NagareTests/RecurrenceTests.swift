import Foundation
import Testing
@testable import Nagare

struct RecurrenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    @Test func relativeDailyRecurrenceUsesTheCurrentMutableDate() throws {
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 7, 23),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 7, 24))
    }

    @Test func relativeWeeklyRecurrenceAdvancesFromTheCurrentDate() throws {
        let rule = try RecurrenceRule.relative(every: 2, unit: .week)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 7, 23),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 8, 6))
    }

    @Test func relativeMonthlyRecurrenceClampsToLeapYearMonthEnd() throws {
        let rule = try RecurrenceRule.relative(every: 1, unit: .month)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2024, 1, 31),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2024, 2, 29))
    }

    @Test func relativeMonthlyRecurrenceClampsToNonLeapYearMonthEnd() throws {
        let rule = try RecurrenceRule.relative(every: 1, unit: .month)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2025, 1, 31),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2025, 2, 28))
    }

    @Test func relativeYearlyRecurrencePreservesMonthAndDay() throws {
        let rule = try RecurrenceRule.relative(every: 1, unit: .year)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 8, 3),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2027, 8, 3))
    }

    @Test func relativeYearlyRecurrenceClampsLeapDay() throws {
        let rule = try RecurrenceRule.relative(every: 1, unit: .year)

        let next = try RecurrenceCalculator.nextDate(
            after: date(2024, 2, 29),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2025, 2, 28))
    }

    @Test func relativeRecurrenceExposesExactlyOneVirtualDate() throws {
        let rule = try RecurrenceRule.relative(every: 10, unit: .day)

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 1, 2),
            calendar: calendar
        )

        #expect(dates == [date(2026, 1, 11)])
    }

    @Test func relativeRecurrenceStopsBeforeDateAfterInclusiveCutoff() throws {
        let rule = try RecurrenceRule.relative(
            every: 2,
            unit: .day,
            repeatUntil: date(2026, 1, 2, hour: 18),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 2, 1),
            calendar: calendar
        )

        #expect(rule.repeatUntil == date(2026, 1, 2))
        #expect(dates.isEmpty)
    }

    @Test func absoluteDayReferenceIsNormalizedToStartOfDay() throws {
        let rule = try RecurrenceRule.absolute(
            every: 3,
            unit: .day,
            reference: date(2026, 1, 1, hour: 18),
            calendar: calendar
        )

        #expect(rule.reference == date(2026, 1, 1))
    }

    @Test func absoluteWeeklyReferenceIsNormalizedToMonday() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [0],
            reference: date(2026, 1, 7),
            calendar: calendar
        )

        #expect(rule.reference == date(2026, 1, 5))
    }

    @Test func weeklyNormalizationIgnoresCalendarFirstWeekday() throws {
        var sundayFirstCalendar = calendar
        sundayFirstCalendar.firstWeekday = 1

        let reference = try RecurrenceCalculator.normalizedReference(
            date(2026, 1, 11),
            for: .week,
            calendar: sundayFirstCalendar
        )

        #expect(reference == date(2026, 1, 5))
    }

    @Test func absoluteMonthlyReferenceIsNormalizedToFirstDay() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [0],
            reference: date(2026, 1, 23, hour: 9),
            calendar: calendar
        )

        #expect(rule.reference == date(2026, 1, 1))
    }

    @Test func absoluteDayRecurrencePreservesReferencePhase() throws {
        let rule = try RecurrenceRule.absolute(
            every: 3,
            unit: .day,
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 2),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 4)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 4),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 7)
        )
    }

    @Test func absoluteDayRecurrenceStartsAtFutureReference() throws {
        let rule = try RecurrenceRule.absolute(
            every: 3,
            unit: .day,
            reference: date(2026, 1, 10),
            calendar: calendar
        )

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 1, 2),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 1, 10))
    }

    @Test func absoluteYearlyRecurrencePreservesBirthdayPhase() throws {
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .year,
            reference: date(2026, 8, 3),
            calendar: calendar
        )

        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2027, 10, 1),
                using: rule,
                calendar: calendar
            ) == date(2028, 8, 3)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2028, 8, 3),
                using: rule,
                calendar: calendar
            ) == date(2030, 8, 3)
        )
    }

    @Test func absoluteLeapDayRecurrenceReturnsToLeapDay() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .year,
            reference: date(2024, 2, 29),
            calendar: calendar
        )

        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2024, 2, 29),
                using: rule,
                calendar: calendar
            ) == date(2025, 2, 28)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2027, 2, 28),
                using: rule,
                calendar: calendar
            ) == date(2028, 2, 29)
        )
    }

    @Test func zeroBasedWeeklyAnchorsStartOnMonday() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .week,
            anchors: [6, 0, 3],
            reference: date(2026, 1, 5),
            calendar: calendar
        )

        #expect(rule.anchors == [0, 3, 6])
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 5),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 8)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 8),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 11)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 11),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 12)
        )
    }

    @Test func absoluteWeeklyRecurrencePreservesMultiweekPhase() throws {
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [0],
            reference: date(2026, 1, 7),
            calendar: calendar
        )

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 1, 13),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 1, 19))
    }

    @Test func absoluteWeeklyRecurrenceWorksAcrossYearBoundary() throws {
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .week,
            anchors: [0],
            reference: date(2025, 12, 22),
            calendar: calendar
        )

        let next = try RecurrenceCalculator.nextDate(
            after: date(2025, 12, 29),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 1, 5))
    }

    @Test func zeroBasedMonthlyAnchorsRepresentFirstFifteenthAndThirtyFirst() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [30, 0, 14],
            reference: date(2026, 1, 20),
            calendar: calendar
        )

        #expect(rule.anchors == [0, 14, 30])
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 1),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 15)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 15),
                using: rule,
                calendar: calendar
            ) == date(2026, 1, 31)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 31),
                using: rule,
                calendar: calendar
            ) == date(2026, 2, 1)
        )
    }

    @Test func absoluteMonthlyRecurrenceClampsThirtyFirstToMonthEnd() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [30],
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 1, 31),
                using: rule,
                calendar: calendar
            ) == date(2026, 2, 28)
        )
        #expect(
            try RecurrenceCalculator.nextDate(
                after: date(2026, 2, 28),
                using: rule,
                calendar: calendar
            ) == date(2026, 3, 31)
        )
    }

    @Test func clampedMonthlyAnchorsDoNotDuplicateTheSameDate() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [27, 28, 29, 30],
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 2, 27),
            using: rule,
            absoluteThrough: date(2026, 3, 1),
            calendar: calendar
        )

        #expect(dates == [date(2026, 2, 28)])
    }

    @Test func absoluteMonthlyRecurrencePreservesMultimonthPhase() throws {
        let rule = try RecurrenceRule.absolute(
            every: 2,
            unit: .month,
            anchors: [9],
            reference: date(2026, 1, 20),
            calendar: calendar
        )

        let next = try RecurrenceCalculator.nextDate(
            after: date(2026, 2, 15),
            using: rule,
            calendar: calendar
        )

        #expect(next == date(2026, 3, 10))
    }

    @Test func absoluteProjectionIncludesEveryDateThroughInclusiveHorizon() throws {
        let rule = try RecurrenceRule.absolute(
            every: 3,
            unit: .day,
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 1, 10),
            calendar: calendar
        )

        #expect(
            dates == [
                date(2026, 1, 4),
                date(2026, 1, 7),
                date(2026, 1, 10)
            ]
        )
    }

    @Test func absoluteProjectionIncludesCutoffDateAndNothingAfterIt() throws {
        let rule = try RecurrenceRule.absolute(
            every: 3,
            unit: .day,
            reference: date(2026, 1, 1),
            repeatUntil: date(2026, 1, 7),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 1, 31),
            calendar: calendar
        )

        #expect(dates == [date(2026, 1, 4), date(2026, 1, 7)])
    }

    @Test func absoluteProjectionCanRepresentSixMonthUpcomingWindow() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [0, 14],
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 7, 1),
            calendar: calendar
        )

        #expect(dates.first == date(2026, 1, 15))
        #expect(dates.last == date(2026, 7, 1))
        #expect(dates.count == 12)
    }

    @Test func absoluteProjectionReturnsNoRowsBeforeNextOccurrence() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .month,
            anchors: [0],
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        let dates = try RecurrenceCalculator.virtualDates(
            after: date(2026, 1, 1),
            using: rule,
            absoluteThrough: date(2026, 1, 31),
            calendar: calendar
        )

        #expect(dates.isEmpty)
    }

    @Test func recurrenceDatesStayAtLocalStartOfDayAcrossDST() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let rule = try RecurrenceRule.relative(every: 1, unit: .day)
        let marchSeventh = localDate(
            2026,
            3,
            7,
            calendar: losAngeles
        )

        let marchEighth = try RecurrenceCalculator.nextDate(
            after: marchSeventh,
            using: rule,
            calendar: losAngeles
        )
        let marchNinth = try RecurrenceCalculator.nextDate(
            after: marchEighth,
            using: rule,
            calendar: losAngeles
        )

        #expect(
            losAngeles.dateComponents(
                [.year, .month, .day, .hour],
                from: marchEighth
            ) == DateComponents(
                year: 2026,
                month: 3,
                day: 8,
                hour: 0
            )
        )
        #expect(
            losAngeles.dateComponents(
                [.year, .month, .day, .hour],
                from: marchNinth
            ) == DateComponents(
                year: 2026,
                month: 3,
                day: 9,
                hour: 0
            )
        )
    }

    @Test func rejectsZeroAndNegativeIntervals() {
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.relative(every: 0, unit: .day)
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: -1,
                unit: .day,
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
    }

    @Test func rejectsMissingAbsoluteAnchors() {
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .week,
                anchors: [],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .month,
                anchors: [],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
    }

    @Test func rejectsOutOfRangeAnchors() {
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .week,
                anchors: [-1, 0],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .week,
                anchors: [7],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .month,
                anchors: [31],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
    }

    @Test func rejectsDuplicateAndUnexpectedAnchors() {
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .week,
                anchors: [0, 0],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .day,
                anchors: [0],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
        #expect(throws: RecurrenceError.self) {
            try RecurrenceRule.absolute(
                every: 1,
                unit: .year,
                anchors: [0],
                reference: date(2026, 1, 1),
                calendar: calendar
            )
        }
    }

    @Test func projectionLimitFailsLoudly() throws {
        let rule = try RecurrenceRule.absolute(
            every: 1,
            unit: .day,
            reference: date(2026, 1, 1),
            calendar: calendar
        )

        #expect(throws: RecurrenceError.self) {
            try RecurrenceCalculator.virtualDates(
                after: date(2026, 1, 1),
                using: rule,
                absoluteThrough: date(2026, 1, 10),
                calendar: calendar,
                maximumCount: 3
            )
        }
    }

    @Test func recurrenceErrorsCarryDiagnosticCodes() {
        let error = RecurrenceError.invalidInterval(0)

        #expect(error.localizedDescription.contains("RECURRENCE-001"))
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0
    ) -> Date {
        localDate(
            year,
            month,
            day,
            hour: hour,
            calendar: calendar
        )
    }

    private func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
