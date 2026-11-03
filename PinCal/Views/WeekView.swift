import PinCalCore
import SwiftUI

struct WeekView: View {
    let store: CalendarStore
    @Bindable var model: PickerModel
    let prefs: Preferences

    private let hourHeight: CGFloat = 48
    private let gutterWidth: CGFloat = 52
    @State private var scrollPosition = ScrollPosition(edge: .top)

    var body: some View {
        let days = model.days(includeWeekends: prefs.showWeekends)
        // Own reservations don't make a selected slot "conflict"; they usually are that slot.
        let busy = BusyCalculator.busyIntervals(store.events.filter { !$0.isHold }.map(\.info), rules: prefs.busyRules)
        let calendar = model.calendar

        VStack(spacing: 0) {
            header(days: days, calendar: calendar)
            allDayStrip(days: days, calendar: calendar)
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    TimeGutter(hourHeight: hourHeight)
                        .frame(width: gutterWidth)
                    ForEach(days, id: \.self) { day in
                        DayColumn(
                            day: day,
                            events: timedEvents(on: day, calendar: calendar),
                            busy: busy,
                            model: model,
                            store: store,
                            prefs: prefs,
                            hourHeight: hourHeight
                        )
                        .overlay(alignment: .leading) { Divider() }
                    }
                }
                .frame(height: hourHeight * 24)
            }
            .scrollPosition($scrollPosition)
            .onAppear { scrollToWorkHours() }
        }
    }

    private func scrollToWorkHours() {
        let minutes = max(prefs.workStartMinutes - 60, 0)
        scrollPosition.scrollTo(y: CGFloat(minutes) / 60 * hourHeight)
    }

    /// Calendars unchecked in the sidebar are hidden, like in Calendar.app.
    private var visibleEvents: [DisplayEvent] {
        store.events.filter { prefs.countsAsBusy(calendarID: $0.calendarID) }
    }

    private func timedEvents(on day: Date, calendar: Calendar) -> [DisplayEvent] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return visibleEvents.filter { !$0.isAllDay && $0.start < next && $0.end > day }
    }

    private func allDayEvents(on day: Date, calendar: Calendar) -> [DisplayEvent] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return visibleEvents.filter { $0.isAllDay && $0.start < next && $0.end > day }
    }

    private func header(days: [Date], calendar: Calendar) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutterWidth, height: 1)
            ForEach(days, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                HStack(spacing: 6) {
                    Text(day, format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(.secondary)
                    Text(day, format: .dateTime.day())
                        .fontWeight(.semibold)
                        .foregroundStyle(isToday ? .white : .primary)
                        .frame(minWidth: 24, minHeight: 24)
                        .background { if isToday { Circle().fill(.red) } }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private func allDayStrip(days: [Date], calendar: Calendar) -> some View {
        let perDay = days.map { allDayEvents(on: $0, calendar: calendar) }
        if perDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: gutterWidth, alignment: .trailing)
                    .padding(.trailing, 6)
                    .offset(x: -6)
                ForEach(Array(zip(days, perDay)), id: \.0) { _, events in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(events.prefix(3)) { event in
                            Text(event.title)
                                .font(.caption)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(event.color.opacity(0.25), in: .rect(cornerRadius: 3))
                        }
                        if events.count > 3 {
                            Text("+\(events.count - 3)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

struct TimeGutter: View {
    let hourHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(1..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
                    .offset(y: CGFloat(hour) * hourHeight - 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
