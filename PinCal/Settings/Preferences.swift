import PinCalCore
import Foundation
import Observation

/// User settings, persisted in UserDefaults.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    /// Calendars that do not count as busy. Opt-out so newly added calendars count by default.
    var excludedCalendarIDs: Set<String> { didSet { defaults.set(Array(excludedCalendarIDs), forKey: Keys.excluded) } }
    /// Working hours in minutes after midnight; used for shading and initial scroll position.
    var workStartMinutes: Int { didSet { defaults.set(workStartMinutes, forKey: Keys.workStart) } }
    var workEndMinutes: Int { didSet { defaults.set(workEndMinutes, forKey: Keys.workEnd) } }
    var showWeekends: Bool { didSet { defaults.set(showWeekends, forKey: Keys.weekends) } }
    var allDayCountsAsBusy: Bool { didSet { defaults.set(allDayCountsAsBusy, forKey: Keys.allDay) } }
    var defaultLanguage: CopyLanguage { didSet { defaults.set(defaultLanguage.rawValue, forKey: Keys.language) } }
    var includeIntro: Bool { didSet { defaults.set(includeIntro, forKey: Keys.intro) } }
    var includeTimeZone: Bool { didSet { defaults.set(includeTimeZone, forKey: Keys.timeZone) } }
    /// Fixed slot length in minutes for click-to-place; 0 means off (drag only).
    var slotMinutes: Int { didSet { defaults.set(slotMinutes, forKey: Keys.slot) } }
    /// Calendar for reservations; nil means the automatic "Pin-Cal" calendar.
    var holdCalendarID: String? { didSet { defaults.set(holdCalendarID, forKey: Keys.holdCalendar) } }
    /// Title for reserved events.
    var holdTitle: String { didSet { defaults.set(holdTitle, forKey: Keys.holdTitle) } }
    /// Use the user's own Markdown message instead of the built-in text.
    var useCustomMessage: Bool { didSet { defaults.set(useCustomMessage, forKey: Keys.customOn) } }
    /// Custom messages per copy language (raw value → Markdown).
    var customTemplates: [String: String] { didSet { defaults.set(customTemplates, forKey: Keys.templates) } }

    func template(for language: CopyLanguage) -> String {
        customTemplates[language.rawValue] ?? language.defaultTemplate
    }

    func setTemplate(_ text: String, for language: CopyLanguage) {
        customTemplates[language.rawValue] = text
    }

    /// Optional menu bar icon; off by default.
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Keys.menuBar) } }

    var busyRules: BusyRules {
        BusyRules(excludedCalendarIDs: excludedCalendarIDs, allDayCountsAsBusy: allDayCountsAsBusy)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.workStart: 9 * 60,
            Keys.workEnd: 17 * 60 + 30,
            Keys.weekends: true,
            Keys.allDay: false,
            Keys.language: CopyLanguage.dutch.rawValue,
            Keys.intro: true,
            Keys.timeZone: false,
            Keys.slot: 0,
            Keys.holdTitle: "Voorlopig",
            Keys.menuBar: false,
            Keys.customOn: false,
        ])
        excludedCalendarIDs = Set(defaults.stringArray(forKey: Keys.excluded) ?? [])
        workStartMinutes = defaults.integer(forKey: Keys.workStart)
        workEndMinutes = defaults.integer(forKey: Keys.workEnd)
        showWeekends = defaults.bool(forKey: Keys.weekends)
        allDayCountsAsBusy = defaults.bool(forKey: Keys.allDay)
        defaultLanguage = CopyLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .dutch
        includeIntro = defaults.bool(forKey: Keys.intro)
        includeTimeZone = defaults.bool(forKey: Keys.timeZone)
        slotMinutes = defaults.integer(forKey: Keys.slot)
        holdCalendarID = defaults.string(forKey: Keys.holdCalendar)
        holdTitle = defaults.string(forKey: Keys.holdTitle) ?? "Voorlopig"
        showMenuBarIcon = defaults.bool(forKey: Keys.menuBar)
        useCustomMessage = defaults.bool(forKey: Keys.customOn)
        customTemplates = defaults.dictionary(forKey: Keys.templates) as? [String: String] ?? [:]
    }

    func countsAsBusy(calendarID: String) -> Bool { !excludedCalendarIDs.contains(calendarID) }

    func setCountsAsBusy(_ counts: Bool, calendarID: String) {
        if counts { excludedCalendarIDs.remove(calendarID) } else { excludedCalendarIDs.insert(calendarID) }
    }

    private enum Keys {
        static let excluded = "excludedCalendarIDs"
        static let workStart = "workStartMinutes"
        static let workEnd = "workEndMinutes"
        static let weekends = "showWeekends"
        static let allDay = "allDayCountsAsBusy"
        static let language = "defaultLanguage"
        static let intro = "includeIntro"
        static let timeZone = "includeTimeZone"
        static let slot = "slotMinutes"
        static let holdCalendar = "holdCalendarID"
        static let holdTitle = "holdTitle"
        static let menuBar = "showMenuBarIcon"
        static let customOn = "useCustomMessage"
        static let templates = "customTemplates"
    }
}
