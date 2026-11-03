import SwiftUI

/// Calendar list grouped by account with coloured checkboxes, plus a mini month for navigation,
/// modelled on the Calendar.app sidebar.
struct CalendarSidebar: View {
    let store: CalendarStore
    @Bindable var model: PickerModel
    @Bindable var prefs: Preferences

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.sources) { source in
                    Section(source.title) {
                        ForEach(source.calendars) { calendar in
                            CalendarRow(
                                calendar: calendar,
                                isOn: Binding(
                                    get: { prefs.countsAsBusy(calendarID: calendar.id) },
                                    set: { prefs.setCountsAsBusy($0, calendarID: calendar.id) }
                                )
                            )
                            .contextMenu {
                                Button("Show Only This Calendar") { showOnly(calendar.id) }
                                Button("Show All Calendars") { prefs.excludedCalendarIDs.removeAll() }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().padding(.horizontal, 12)
            MiniMonth(model: model)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
    }

    private func showOnly(_ id: String) {
        let all = store.sources.flatMap(\.calendars).map(\.id)
        prefs.excludedCalendarIDs = Set(all.filter { $0 != id })
    }
}

private struct CalendarRow: View {
    let calendar: CalendarEntry
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Toggle(isOn: $isOn) {
                Text(calendar.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isOn ? .primary : .secondary)
            }
            .toggleStyle(.checkbox)
            .tint(calendar.color)
            Spacer(minLength: 4)
            if calendar.isSubscribed {
                Image(systemName: "dot.radiowaves.right")
                    .foregroundStyle(.secondary)
                    .help("Subscribed calendar")
            }
        }
    }
}

/// Month grid like Calendar.app's sidebar: week numbers, today circled, visible week highlighted.
struct MiniMonth: View {
    @Bindable var model: PickerModel
    @State private var month: Date = Date()

    private var calendar: Calendar { model.calendar }

    var body: some View {
        let weeks = weeksInMonth
        VStack(spacing: 6) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 0, verticalSpacing: 2) {
                GridRow {
                    Text("").gridColumnAlignment(.trailing)
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(weeks, id: \.self) { weekStart in
                    let isVisibleWeek = weekStart == model.weekStart
                    GridRow {
                        Text("\(calendar.component(.weekOfYear, from: weekStart))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)
                            .padding(.trailing, 4)
                        ForEach(days(from: weekStart), id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    .background {
                        if isVisibleWeek {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.18))
                                .padding(.leading, 26)
                        }
                    }
                }
            }
        }
        .onAppear { month = model.weekStart }
        .onChange(of: model.weekStart) { _, new in
            if !calendar.isDate(new, equalTo: month, toGranularity: .month),
               !calendar.isDate(calendar.date(byAdding: .day, value: 6, to: new) ?? new, equalTo: month, toGranularity: .month) {
                month = new
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let isToday = calendar.isDateInToday(day)
        return Button { model.go(to: day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.callout.monospacedDigit().weight(isToday ? .semibold : .regular))
                .foregroundStyle(inMonth ? .primary : .tertiary)
                .frame(width: 26, height: 26)
                .background { if isToday { Circle().fill(.secondary.opacity(0.5)) } }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var weeksInMonth: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        var weeks: [Date] = []
        var cursor = PickerModel.startOfWeek(interval.start, calendar: calendar)
        // Always six rows so the sidebar doesn't jump between months.
        for _ in 0..<6 {
            weeks.append(cursor)
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) ?? cursor
        }
        return weeks
    }

    private func days(from weekStart: Date) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func shift(_ months: Int) {
        if let d = calendar.date(byAdding: .month, value: months, to: month) { month = d }
    }
}
