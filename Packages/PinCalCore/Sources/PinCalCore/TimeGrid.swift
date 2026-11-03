import Foundation

/// Converts between wall-clock minutes within a day (0...1440) and dates.
/// Uses wall-clock components so days with a DST switch still line up with the grid.
public enum TimeGrid {
    public static let minutesPerDay = 24 * 60

    /// Wall-clock minutes of `date` within the day starting at `dayStart`, clamped to 0...1440.
    public static func minutes(of date: Date, inDayStarting dayStart: Date, calendar: Calendar) -> Double {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        if date <= dayStart { return 0 }
        if date >= nextDay { return Double(minutesPerDay) }
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// Date at `minutes` wall-clock minutes into the day starting at `dayStart`.
    public static func date(atMinutes minutes: Int, inDayStarting dayStart: Date, calendar: Calendar) -> Date {
        let clamped = min(max(minutes, 0), minutesPerDay)
        if clamped == minutesPerDay {
            return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        }
        return calendar.date(bySettingHour: clamped / 60, minute: clamped % 60, second: 0, of: dayStart)
            ?? dayStart.addingTimeInterval(TimeInterval(clamped * 60))
    }

    /// Rounds minutes to the grid step and clamps to 0...1440.
    public static func snap(_ minutes: Double, step: Int = 15, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        let snapped = Int((minutes / Double(step)).rounded(rule)) * step
        return min(max(snapped, 0), minutesPerDay)
    }
}

/// Side-by-side placement for overlapping events in a day column.
public enum ColumnLayout {
    public struct Placement: Sendable, Equatable {
        public let column: Int
        public let columnCount: Int
        public init(column: Int, columnCount: Int) {
            self.column = column
            self.columnCount = columnCount
        }
    }

    /// Returns one placement per input interval, in input order.
    public static func layout(_ intervals: [DateInterval]) -> [Placement] {
        let order = intervals.indices.sorted {
            let a = intervals[$0], b = intervals[$1]
            return a.start != b.start ? a.start < b.start : a.duration > b.duration
        }
        var columns = Array(repeating: 0, count: intervals.count)
        var counts = Array(repeating: 1, count: intervals.count)
        var cluster: [Int] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func closeCluster() {
            for i in cluster { counts[i] = columnEnds.count }
            cluster.removeAll()
            columnEnds.removeAll()
        }

        for i in order {
            let interval = intervals[i]
            if interval.start >= clusterEnd { closeCluster() }
            if let free = columnEnds.firstIndex(where: { $0 <= interval.start }) {
                columns[i] = free
                columnEnds[free] = interval.end
            } else {
                columns[i] = columnEnds.count
                columnEnds.append(interval.end)
            }
            cluster.append(i)
            clusterEnd = cluster.count == 1 ? interval.end : max(clusterEnd, interval.end)
        }
        closeCluster()
        return intervals.indices.map { Placement(column: columns[$0], columnCount: counts[$0]) }
    }
}
