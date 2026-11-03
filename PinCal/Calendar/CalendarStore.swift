import AppKit
import PinCalCore
import EventKit
import Observation
import SwiftUI

/// A read-only snapshot of an `EKEvent` for display.
struct DisplayEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let color: Color
    let info: CalendarEventInfo
    /// EventKit identifier, used to release reservations.
    let eventIdentifier: String?
    /// Set when Pin-Cal created this event as a reservation; shared by all slots reserved together.
    let holdGroup: String?

    var isHold: Bool { holdGroup != nil }

    var interval: DateInterval { DateInterval(start: start, end: max(end, start)) }
}

struct CalendarSource: Identifiable {
    let id: String
    let title: String
    let calendars: [CalendarEntry]
}

struct CalendarEntry: Identifiable, Hashable {
    let id: String
    let title: String
    let color: Color
    let isWritable: Bool
    let isSubscribed: Bool
}

enum ReservationError: LocalizedError {
    case noWritableSource

    var errorDescription: String? {
        switch self {
        case .noWritableSource: "No calendar account found that Pin-Cal can create a calendar in."
        }
    }
}

/// Wraps EventKit: permission, calendars and events for a date range.
/// The only writes are reservations (events marked with a `pincal://hold/` URL) and their release.
@MainActor
@Observable
final class CalendarStore {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var sources: [CalendarSource] = []
    private(set) var events: [DisplayEvent] = []
    /// Bumped whenever EventKit reports changes so views can refetch.
    private(set) var revision = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var loadedRange: DateInterval?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        }
        updateAccess()
    }

    func requestAccessIfNeeded() async {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            updateAccess()
            return
        }
        _ = try? await store.requestFullAccessToEvents()
        updateAccess()
        if access == .granted {
            reloadCalendars()
            if let range = loadedRange { load(range) }
        }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
        if access == .granted && sources.isEmpty { reloadCalendars() }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func load(_ range: DateInterval) {
        loadedRange = range
        guard access == .granted else { return }
        let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: nil)
        events = store.events(matching: predicate).map(Self.displayEvent)
    }

    private func storeChanged() {
        reloadCalendars()
        if let range = loadedRange { load(range) }
        revision += 1
    }

    private func reloadCalendars() {
        guard access == .granted else { return }
        let calendars = store.calendars(for: .event)
        let grouped = Dictionary(grouping: calendars) { $0.source?.sourceIdentifier ?? "local" }
        sources = grouped.map { id, calendars in
            CalendarSource(
                id: id,
                title: calendars.first?.source?.title ?? "Other",
                calendars: calendars
                    .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                    .map {
                        CalendarEntry(id: $0.calendarIdentifier, title: $0.title,
                                      color: Color(cgColor: $0.cgColor), isWritable: $0.allowsContentModifications,
                                      isSubscribed: $0.type == .subscription)
                    }
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func displayEvent(_ event: EKEvent) -> DisplayEvent {
        let declined = event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        let calendarID = event.calendar?.calendarIdentifier ?? ""
        let info = CalendarEventInfo(
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: calendarID,
            availability: availability(event.availability),
            isDeclined: declined
        )
        return DisplayEvent(
            id: "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSinceReferenceDate)",
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: calendarID,
            color: event.calendar.map { Color(cgColor: $0.cgColor) } ?? .gray,
            info: info,
            eventIdentifier: event.eventIdentifier,
            holdGroup: holdGroup(of: event)
        )
    }

    // MARK: Reservations

    static let holdScheme = "pincal"
    static let autoCalendarTitle = "Pin-Cal"
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let autoCalendarKey = "autoHoldCalendarID"

    /// Reservations are marked by URL and, as a fallback for accounts that drop the URL
    /// (e.g. some Exchange setups), by a tag in the notes.
    private static func holdGroup(of event: EKEvent) -> String? {
        if let url = event.url, url.scheme == holdScheme, url.host() == "hold" {
            return url.lastPathComponent
        }
        guard let notes = event.notes, let range = notes.range(of: "[pincal:") else { return nil }
        let rest = notes[range.upperBound...]
        guard let end = rest.firstIndex(of: "]") else { return nil }
        return String(rest[..<end])
    }

    /// The calendar reservations go into: the chosen one if it is writable, otherwise the
    /// automatic "Pin-Cal" calendar (created on first use in the default account).
    func holdCalendar(preferredID: String?) throws -> EKCalendar {
        if let id = preferredID, let calendar = store.calendar(withIdentifier: id), calendar.allowsContentModifications {
            return calendar
        }
        if let id = defaults.string(forKey: Self.autoCalendarKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.autoCalendarTitle && $0.allowsContentModifications }) {
            defaults.set(existing.calendarIdentifier, forKey: Self.autoCalendarKey)
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.autoCalendarTitle
        calendar.cgColor = CGColor(red: 0.92, green: 0.12, blue: 0.14, alpha: 1)
        guard let source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
        else { throw ReservationError.noWritableSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: Self.autoCalendarKey)
        return calendar
    }

    /// Creates one busy event per slot. Returns the calendar title used.
    @discardableResult
    func reserve(_ intervals: [DateInterval], title: String, calendarID: String?) throws -> String {
        let calendar = try holdCalendar(preferredID: calendarID)
        let group = UUID().uuidString
        for interval in intervals {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = title
            event.startDate = interval.start
            event.endDate = interval.end
            event.availability = .busy
            event.url = URL(string: "\(Self.holdScheme)://hold/\(group)")
            event.notes = "Reserved with Pin-Cal [pincal:\(group)]"
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        storeChanged()
        return calendar.title
    }

    /// Deletes reservations. Only touches events Pin-Cal created.
    func release(_ events: [DisplayEvent]) throws {
        for display in events where display.isHold {
            guard let id = display.eventIdentifier, let event = store.event(withIdentifier: id),
                  Self.holdGroup(of: event) != nil else { continue }
            try store.remove(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        storeChanged()
    }

    /// Deletes every reservation made together with `event`, also outside the visible week.
    func releaseGroup(of event: DisplayEvent) throws {
        guard let group = event.holdGroup else { return }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        for match in store.events(matching: predicate) where Self.holdGroup(of: match) == group {
            try store.remove(match, span: .thisEvent, commit: false)
        }
        try store.commit()
        storeChanged()
    }

    /// Loaded reservations made together with `event`.
    func holdSiblings(of event: DisplayEvent) -> [DisplayEvent] {
        guard let group = event.holdGroup else { return [] }
        return events.filter { $0.holdGroup == group }
    }

    private static func availability(_ a: EKEventAvailability) -> EventAvailability {
        switch a {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        default: .notSupported
        }
    }
}
