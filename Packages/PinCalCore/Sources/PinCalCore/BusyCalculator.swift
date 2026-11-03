import Foundation

/// Mirrors `EKEventAvailability` without depending on EventKit.
public enum EventAvailability: Sendable, Hashable {
    case notSupported, busy, free, tentative, unavailable
}

/// The calendar-event facts needed to decide whether time is busy.
public struct CalendarEventInfo: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var availability: EventAvailability
    public var isDeclined: Bool

    public init(
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        calendarID: String,
        availability: EventAvailability = .busy,
        isDeclined: Bool = false
    ) {
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.availability = availability
        self.isDeclined = isDeclined
    }
}

public struct BusyRules: Sendable, Hashable {
    /// Calendars that should not count as busy (opt-out, so new calendars count by default).
    public var excludedCalendarIDs: Set<String>
    public var allDayCountsAsBusy: Bool

    public init(excludedCalendarIDs: Set<String> = [], allDayCountsAsBusy: Bool = false) {
        self.excludedCalendarIDs = excludedCalendarIDs
        self.allDayCountsAsBusy = allDayCountsAsBusy
    }
}

public enum BusyCalculator {
    public static func countsAsBusy(_ event: CalendarEventInfo, rules: BusyRules) -> Bool {
        guard event.end > event.start else { return false }
        if rules.excludedCalendarIDs.contains(event.calendarID) { return false }
        if event.isDeclined { return false }
        if event.availability == .free { return false }
        if event.isAllDay && !rules.allDayCountsAsBusy { return false }
        return true
    }

    /// Sorted, merged busy intervals.
    public static func busyIntervals(_ events: [CalendarEventInfo], rules: BusyRules) -> [DateInterval] {
        merge(events.filter { countsAsBusy($0, rules: rules) }.map { DateInterval(start: $0.start, end: $0.end) })
    }

    /// Merges overlapping and touching intervals into a sorted list.
    public static func merge(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    public static func overlapsBusy(_ interval: DateInterval, busy: [DateInterval]) -> Bool {
        busy.contains { $0.start < interval.end && interval.start < $0.end }
    }
}
