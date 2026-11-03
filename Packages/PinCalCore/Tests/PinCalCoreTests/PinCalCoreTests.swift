import Foundation
import Testing
@testable import PinCalCore

let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = amsterdam
    return c
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func slot(_ d: Int, _ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int, month: Int = 11, year: Int = 2026) -> DateInterval {
    DateInterval(start: date(year, month, d, h1, m1), end: date(year, month, d, h2, m2))
}

@Suite struct BusyCalculatorTests {
    @Test func mergesOverlappingAndAdjacent() {
        let merged = BusyCalculator.merge([slot(4, 11, 0, 12, 0), slot(4, 9, 0, 10, 0), slot(4, 10, 0, 10, 30), slot(4, 11, 30, 13, 0)])
        #expect(merged == [slot(4, 9, 0, 10, 30), slot(4, 11, 0, 13, 0)])
    }

    @Test func skipsFreeDeclinedExcludedAndAllDay() {
        let events = [
            CalendarEventInfo(start: date(2026, 11, 4, 9), end: date(2026, 11, 4, 10), calendarID: "work"),
            CalendarEventInfo(start: date(2026, 11, 4, 10), end: date(2026, 11, 4, 11), calendarID: "work", availability: .free),
            CalendarEventInfo(start: date(2026, 11, 4, 11), end: date(2026, 11, 4, 12), calendarID: "work", isDeclined: true),
            CalendarEventInfo(start: date(2026, 11, 4, 12), end: date(2026, 11, 4, 13), calendarID: "birthdays"),
            CalendarEventInfo(start: date(2026, 11, 4), end: date(2026, 11, 5), isAllDay: true, calendarID: "work"),
            CalendarEventInfo(start: date(2026, 11, 4, 14), end: date(2026, 11, 4, 15), calendarID: "work", availability: .tentative),
        ]
        let rules = BusyRules(excludedCalendarIDs: ["birthdays"])
        #expect(BusyCalculator.busyIntervals(events, rules: rules) == [slot(4, 9, 0, 10, 0), slot(4, 14, 0, 15, 0)])

        let allDay = BusyRules(excludedCalendarIDs: ["birthdays"], allDayCountsAsBusy: true)
        #expect(BusyCalculator.busyIntervals(events, rules: allDay) == [DateInterval(start: date(2026, 11, 4), end: date(2026, 11, 5))])
    }

    @Test func overlapDetection() {
        let busy = [slot(4, 9, 0, 10, 0)]
        #expect(BusyCalculator.overlapsBusy(slot(4, 9, 30, 10, 30), busy: busy))
        #expect(!BusyCalculator.overlapsBusy(slot(4, 10, 0, 11, 0), busy: busy))
    }
}

@Suite struct ProposalSetTests {
    @Test func addMergesAndKeepsSorted() {
        var set = ProposalSet()
        let first = set.add(slot(5, 14, 0, 15, 0))
        set.add(slot(4, 10, 0, 11, 0))
        let merged = set.add(slot(5, 15, 0, 15, 30))
        #expect(merged == first)
        #expect(set.intervals == [slot(4, 10, 0, 11, 0), slot(5, 14, 0, 15, 30)])
    }

    @Test func updateThenNormalizeMerges() {
        var set = ProposalSet()
        let a = set.add(slot(4, 9, 0, 10, 0))
        set.add(slot(4, 11, 0, 12, 0))
        set.update(id: a, to: slot(4, 9, 0, 11, 15))
        #expect(set.count == 2)
        set.normalize(id: a)
        #expect(set.intervals == [slot(4, 9, 0, 12, 0)])
        #expect(set.items.first?.id == a)
    }

    @Test func remove() {
        var set = ProposalSet()
        let a = set.add(slot(4, 9, 0, 10, 0))
        set.remove(id: a)
        #expect(set.isEmpty)
    }
}

@Suite struct TimeGridTests {
    @Test func snapping() {
        #expect(TimeGrid.snap(607) == 600)
        #expect(TimeGrid.snap(608) == 615)
        #expect(TimeGrid.snap(-20) == 0)
        #expect(TimeGrid.snap(1500) == 1440)
        #expect(TimeGrid.snap(614, rule: .down) == 600)
    }

    @Test func roundTripOnDSTDay() {
        // 25 October 2026: clocks go back in the Netherlands.
        let day = date(2026, 10, 25)
        let tenAM = TimeGrid.date(atMinutes: 600, inDayStarting: day, calendar: calendar)
        #expect(tenAM == date(2026, 10, 25, 10))
        #expect(TimeGrid.minutes(of: tenAM, inDayStarting: day, calendar: calendar) == 600)
        #expect(TimeGrid.date(atMinutes: 1440, inDayStarting: day, calendar: calendar) == date(2026, 10, 26))
        #expect(TimeGrid.minutes(of: date(2026, 10, 26, 1), inDayStarting: day, calendar: calendar) == 1440)
    }

    @Test func columnLayout() {
        let placements = ColumnLayout.layout([slot(4, 9, 0, 10, 0), slot(4, 9, 30, 11, 0), slot(4, 10, 0, 10, 30), slot(4, 12, 0, 13, 0)])
        #expect(placements == [
            .init(column: 0, columnCount: 2),
            .init(column: 1, columnCount: 2),
            .init(column: 0, columnCount: 2),
            .init(column: 0, columnCount: 1),
        ])
    }
}

@Suite struct AvailabilityFormatterTests {
    let slots = [slot(5, 9, 0, 10, 0), slot(4, 14, 0, 15, 30), slot(4, 10, 0, 11, 0)]

    @Test func dutch() {
        let f = AvailabilityFormatter(language: .dutch, timeZone: amsterdam, includeTimeZone: true, referenceDate: date(2026, 11, 3))
        #expect(f.plainText(slots) == """
        Ik ben beschikbaar op de volgende momenten:
        • woensdag 4 november: 10:00–11:00, 14:00–15:30
        • donderdag 5 november: 09:00–10:00
        (tijden in CET)
        """)
    }

    @Test func englishWithoutExtras() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, includeIntro: false, includeTimeZone: false, referenceDate: date(2026, 11, 3))
        #expect(f.plainText(slots) == """
        • Wednesday 4 November: 10:00–11:00, 14:00–15:30
        • Thursday 5 November: 09:00–10:00
        """)
    }

    @Test func yearAndDSTLabelsAndMidnight() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, includeIntro: false, includeTimeZone: true, referenceDate: date(2026, 11, 3))
        let text = f.plainText([
            DateInterval(start: date(2027, 3, 26, 23), end: date(2027, 3, 27)),
            slot(29, 9, 0, 10, 0, month: 3, year: 2027),
        ])
        #expect(text == """
        • Friday 26 March 2027: 23:00–24:00
        • Monday 29 March 2027: 09:00–10:00
        (times in CET/CEST)
        """)
    }

    @Test func htmlEscapesAndBolds() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, includeIntro: false, includeTimeZone: false, referenceDate: date(2026, 11, 3))
        #expect(f.html([slot(4, 10, 0, 11, 0)]) == "<meta charset=\"utf-8\"><ul><li><b>Wednesday 4 November</b>: 10:00–11:00</li></ul>")
    }

    @Test func german() {
        let f = AvailabilityFormatter(language: .german, timeZone: amsterdam, includeTimeZone: true, referenceDate: date(2026, 11, 3))
        #expect(f.plainText(slots) == """
        Ich bin zu folgenden Zeiten verfügbar:
        • Mittwoch, 4. November: 10:00–11:00, 14:00–15:30
        • Donnerstag, 5. November: 09:00–10:00
        (Zeiten in MEZ)
        """)
    }

    @Test func french() {
        let f = AvailabilityFormatter(language: .french, timeZone: amsterdam, referenceDate: date(2026, 11, 3))
        #expect(f.plainText(slots) == """
        Je suis disponible aux créneaux suivants\u{00A0}:
        • mercredi 4 novembre\u{00A0}: 10h00–11h00, 14h00–15h30
        • jeudi 5 novembre\u{00A0}: 09h00–10h00
        """)
    }

    @Test func spanishWithYear() {
        let f = AvailabilityFormatter(language: .spanish, timeZone: amsterdam, includeTimeZone: true, referenceDate: date(2026, 11, 3))
        #expect(f.plainText([slot(4, 10, 0, 11, 0), slot(5, 9, 0, 10, 0, month: 1, year: 2027)]) == """
        Estoy disponible en los siguientes horarios:
        • miércoles 4 de noviembre: 10:00–11:00
        • martes 5 de enero de 2027: 09:00–10:00
        (horas en CET)
        """)
    }

    @Test func emptyIsEmpty() {
        #expect(AvailabilityFormatter(language: .dutch).plainText([]) == "")
    }
}

@Suite struct MiniMarkdownTests {
    @Test func htmlBlocksAndInline() {
        let md = "Hi **there**,\nsee *this* and _that_\n\n- one\n- [site](https://example.com/a_b*c*)\n\nBye"
        #expect(MiniMarkdown.html(md) == "<p>Hi <b>there</b>,<br>see <i>this</i> and <i>that</i></p><ul><li>one</li><li><a href=\"https://example.com/a_b*c*\">site</a></li></ul><p>Bye</p>")
    }

    @Test func plainStripsMarkers() {
        let md = "Hi **there**\n\n- *one*\n- [site](https://example.com)\n- [https://x.nl](https://x.nl)"
        #expect(MiniMarkdown.plainText(md) == "Hi there\n\n• one\n• site (https://example.com)\n• https://x.nl")
    }

    @Test func escapesHTMLAndUnsafeLinks() {
        // Non-http(s)/mailto links are reduced to their label; no <a> is produced.
        #expect(MiniMarkdown.html("<script> & [x](javascript:alert)") == "<p>&lt;script&gt; &amp; x</p>")
        #expect(MiniMarkdown.html("[x](ftp://a)") == "<p>x</p>")
    }

    @Test func leavesLoneAsterisksAndSnakeCase() {
        #expect(MiniMarkdown.plainText("5 * 3 = 15, file_name_here") == "5 * 3 = 15, file_name_here")
    }
}

@Suite struct TemplateTests {
    let slots = [slot(4, 10, 0, 11, 0), slot(4, 14, 0, 15, 0)]

    @Test func customTemplateWithPlaceholders() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, referenceDate: date(2026, 11, 3),
                                      template: "Hi,\n\n**{count} options** ({timezone}):\n{slots}\n\nCheers")
        #expect(f.plainText(slots) == "Hi,\n\n2 options (CET):\n• Wednesday 4 November: 10:00–11:00, 14:00–15:00\n\nCheers")
        #expect(f.html(slots) == "<meta charset=\"utf-8\"><p>Hi,</p><p><b>2 options</b> (CET):</p><ul><li><b>Wednesday 4 November</b>: 10:00–11:00, 14:00–15:00</li></ul><p>Cheers</p>")
    }

    @Test func missingSlotsPlaceholderAppendsList() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, referenceDate: date(2026, 11, 3), template: "Options:")
        #expect(f.plainText(slots) == "Options:\n\n• Wednesday 4 November: 10:00–11:00, 14:00–15:00")
    }

    @Test func blankTemplateFallsBackToDefault() {
        let f = AvailabilityFormatter(language: .english, timeZone: amsterdam, includeIntro: false, referenceDate: date(2026, 11, 3), template: "  \n")
        #expect(f.plainText(slots) == "• Wednesday 4 November: 10:00–11:00, 14:00–15:00")
    }

    @Test func defaultTemplatesContainSlots() {
        for language in CopyLanguage.allCases { #expect(language.defaultTemplate.contains("{slots}")) }
    }
}
