import AppKit
import PinCalCore
import Foundation
import Observation

/// UI state: visible week, selected slots, copy language.
@MainActor
@Observable
final class PickerModel {
    var calendar: Calendar = .autoupdatingCurrent
    private(set) var weekStart: Date
    var proposals = ProposalSet()
    var language: CopyLanguage
    var toast: String?
    var errorMessage: String?

    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init(language: CopyLanguage) {
        self.language = language
        weekStart = Self.startOfWeek(Date(), calendar: .autoupdatingCurrent)
    }

    static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    func days(includeWeekends: Bool) -> [Date] {
        (0..<7)
            .compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            .filter { includeWeekends || !calendar.isDateInWeekend($0) }
    }

    var weekRange: DateInterval {
        DateInterval(start: weekStart, end: calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
    }

    var weekTitle: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMy")
        let week = calendar.component(.weekOfYear, from: weekStart)
        return "\(f.string(from: weekStart)) · \(String(localized: "Week")) \(week)"
    }

    var isCurrentWeek: Bool { weekStart == Self.startOfWeek(Date(), calendar: calendar) }

    func moveWeek(by weeks: Int) {
        if let d = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) { weekStart = d }
    }

    func go(to date: Date) { weekStart = Self.startOfWeek(date, calendar: calendar) }

    func goToToday() { weekStart = Self.startOfWeek(Date(), calendar: calendar) }

    /// Returns false when there is nothing to copy.
    @discardableResult
    func copy(using prefs: Preferences) -> Bool {
        guard !proposals.isEmpty else { return false }
        let formatter = AvailabilityFormatter(
            language: language,
            timeZone: calendar.timeZone,
            includeIntro: prefs.includeIntro,
            includeTimeZone: prefs.includeTimeZone,
            template: prefs.useCustomMessage ? prefs.template(for: language) : nil
        )
        let intervals = proposals.intervals
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(formatter.html(intervals), forType: .html)
        pasteboard.setString(formatter.plainText(intervals), forType: .string)
        let n = intervals.count
        showToast(language == .dutch
            ? "\(n) \(n == 1 ? "moment" : "momenten") gekopieerd"
            : "Copied \(n) \(n == 1 ? "slot" : "slots")")
        return true
    }

    /// Creates reservation events for the selected slots. The selection stays so it can still be copied.
    func reserve(store: CalendarStore, prefs: Preferences) {
        guard !proposals.isEmpty else { return }
        let title = prefs.holdTitle.trimmingCharacters(in: .whitespaces).isEmpty ? "Voorlopig" : prefs.holdTitle
        do {
            let n = proposals.count
            let calendarTitle = try store.reserve(proposals.intervals, title: title, calendarID: prefs.holdCalendarID)
            showToast(language == .dutch
                ? "\(n) \(n == 1 ? "moment" : "momenten") gereserveerd in \(calendarTitle)"
                : "Reserved \(n) \(n == 1 ? "slot" : "slots") in \(calendarTitle)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func release(_ events: [DisplayEvent], store: CalendarStore) {
        do { try store.release(events) } catch { errorMessage = error.localizedDescription }
    }

    func releaseGroup(of event: DisplayEvent, store: CalendarStore) {
        do { try store.releaseGroup(of: event) } catch { errorMessage = error.localizedDescription }
    }

    func showToast(_ text: String) {
        toastTask?.cancel()
        toast = text
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
