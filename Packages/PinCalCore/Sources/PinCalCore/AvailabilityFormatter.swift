import Foundation

public enum CopyLanguage: String, CaseIterable, Identifiable, Sendable {
    case dutch = "nl"
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"

    public var id: String { rawValue }
    public var shortName: String { rawValue.uppercased() }

    /// Name of the language in that language, for pickers.
    public var nativeName: String {
        switch self {
        case .dutch: "Nederlands"
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        }
    }

    var locale: Locale {
        let identifier = switch self {
        case .dutch: "nl_NL"
        case .english: "en_GB"
        case .german: "de_DE"
        case .french: "fr_FR"
        case .spanish: "es_ES"
        }
        return Locale(identifier: identifier)
    }

    var intro: String {
        switch self {
        case .dutch: "Ik ben beschikbaar op de volgende momenten:"
        case .english: "I'm available at the following times:"
        case .german: "Ich bin zu folgenden Zeiten verfügbar:"
        case .french: "Je suis disponible aux créneaux suivants\u{00A0}:"
        case .spanish: "Estoy disponible en los siguientes horarios:"
        }
    }

    func timeZoneNote(_ zone: String) -> String {
        switch self {
        case .dutch: "(tijden in \(zone))"
        case .english: "(times in \(zone))"
        case .german: "(Zeiten in \(zone))"
        case .french: "(heures en \(zone))"
        case .spanish: "(horas en \(zone))"
        }
    }

    var dayFormat: String {
        switch self {
        case .german: "EEEE, d. MMMM"
        case .spanish: "EEEE d 'de' MMMM"
        default: "EEEE d MMMM"
        }
    }

    var dayYearFormat: String {
        switch self {
        case .german: "EEEE, d. MMMM yyyy"
        case .spanish: "EEEE d 'de' MMMM 'de' yyyy"
        default: "EEEE d MMMM yyyy"
        }
    }

    /// French writes times as 10h00.
    var timeFormat: String { self == .french ? "HH'h'mm" : "HH:mm" }

    /// French puts a (non-breaking) space before a colon.
    var labelSeparator: String { self == .french ? "\u{00A0}: " : ": " }

    /// Starting point for a custom message in Settings.
    public var defaultTemplate: String {
        switch self {
        case .dutch: "Hoi,\n\nIk ben beschikbaar op de volgende momenten:\n\n{slots}\n\nLaat maar weten wat jou het beste uitkomt!"
        case .english: "Hi,\n\nI'm available at the following times:\n\n{slots}\n\nLet me know what works best for you!"
        case .german: "Hallo,\n\nich bin zu folgenden Zeiten verfügbar:\n\n{slots}\n\nSag mir einfach, was dir am besten passt!"
        case .french: "Bonjour,\n\nje suis disponible aux créneaux suivants\u{00A0}:\n\n{slots}\n\nDites-moi ce qui vous convient le mieux\u{00A0}!"
        case .spanish: "Hola:\n\nEstoy disponible en los siguientes horarios:\n\n{slots}\n\n¡Dime qué te viene mejor!"
        }
    }

    /// "24:00" for slots ending at midnight.
    var midnight: String { self == .french ? "24h00" : "24:00" }
}

/// Turns selected slots into text for an email, grouped per day.
///
///     • dinsdag 4 november: 10:00–11:00, 14:00–15:30
public struct AvailabilityFormatter: Sendable {
    public var language: CopyLanguage
    public var timeZone: TimeZone
    public var includeIntro: Bool
    public var includeTimeZone: Bool
    /// Dates outside this date's year get the year appended.
    public var referenceDate: Date
    /// Custom Markdown message with `{slots}`, `{timezone}` and `{count}` placeholders.
    /// When set, `includeIntro` and `includeTimeZone` are ignored.
    public var template: String?

    public init(
        language: CopyLanguage,
        timeZone: TimeZone = .current,
        includeIntro: Bool = true,
        includeTimeZone: Bool = false,
        referenceDate: Date = Date(),
        template: String? = nil
    ) {
        self.language = language
        self.timeZone = timeZone
        self.includeIntro = includeIntro
        self.includeTimeZone = includeTimeZone
        self.referenceDate = referenceDate
        self.template = template
    }

    struct DayGroup {
        let label: String
        let ranges: [String]
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = language.locale
        return calendar
    }

    private func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = language.locale
        f.timeZone = timeZone
        f.calendar = calendar
        f.dateFormat = format
        return f
    }

    func groups(_ intervals: [DateInterval]) -> [DayGroup] {
        let calendar = calendar
        let dayFormatter = formatter(language.dayFormat)
        let dayYearFormatter = formatter(language.dayYearFormat)
        let timeFormatter = formatter(language.timeFormat)
        let referenceYear = calendar.component(.year, from: referenceDate)

        let sorted = intervals.filter { $0.duration > 0 }.sorted { $0.start < $1.start }
        var byDay: [(day: Date, intervals: [DateInterval])] = []
        for interval in sorted {
            let day = calendar.startOfDay(for: interval.start)
            if let last = byDay.last, last.day == day {
                byDay[byDay.count - 1].intervals.append(interval)
            } else {
                byDay.append((day, [interval]))
            }
        }

        return byDay.map { day, intervals in
            let sameYear = calendar.component(.year, from: day) == referenceYear
            let label = (sameYear ? dayFormatter : dayYearFormatter).string(from: day)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            let ranges = intervals.map { interval in
                let end = interval.end == nextDay ? language.midnight : timeFormatter.string(from: interval.end)
                return "\(timeFormatter.string(from: interval.start))–\(end)"
            }
            return DayGroup(label: label, ranges: ranges)
        }
    }

    /// Time zone abbreviation in the message language (e.g. CET in Dutch/English, MEZ in German),
    /// so the result doesn't depend on the Mac's own language settings.
    func timeZoneLabel(_ intervals: [DateInterval]) -> String? {
        let zoneFormatter = formatter("zzz")
        var labels: [String] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let label = zoneFormatter.string(from: interval.start)
            if !labels.contains(label) { labels.append(label) }
        }
        return labels.isEmpty ? nil : labels.joined(separator: "/")
    }

    /// The message as Markdown, before conversion to plain text or HTML.
    public func markdown(_ intervals: [DateInterval]) -> String {
        let groups = groups(intervals)
        guard !groups.isEmpty else { return "" }
        let list = groups
            .map { "- **\($0.label)**\(language.labelSeparator)\($0.ranges.joined(separator: ", "))" }
            .joined(separator: "\n")
        let zone = timeZoneLabel(intervals) ?? timeZone.identifier

        if let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let body = template.contains("{slots}") ? template : template + "\n\n{slots}"
            return body
                .replacingOccurrences(of: "{slots}", with: list)
                .replacingOccurrences(of: "{timezone}", with: zone)
                .replacingOccurrences(of: "{count}", with: "\(groups.reduce(0) { $0 + $1.ranges.count })")
        }

        var lines: [String] = []
        if includeIntro { lines.append(language.intro) }
        lines.append(list)
        if includeTimeZone { lines.append(language.timeZoneNote(zone)) }
        return lines.joined(separator: "\n")
    }

    public func plainText(_ intervals: [DateInterval]) -> String {
        MiniMarkdown.plainText(markdown(intervals))
    }

    public func html(_ intervals: [DateInterval]) -> String {
        let md = markdown(intervals)
        return md.isEmpty ? "" : "<meta charset=\"utf-8\">" + MiniMarkdown.html(md)
    }
}
