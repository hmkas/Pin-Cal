import AppKit
import PinCalCore
import SwiftUI

struct SettingsView: View {
    let store: CalendarStore
    @Bindable var prefs: Preferences
    @State private var editLanguage: CopyLanguage = .dutch

    var body: some View {
        TabView {
            Tab("Calendars", systemImage: "calendar") { calendarsTab }
            Tab("Week", systemImage: "clock") { weekTab }
            Tab("Copy", systemImage: "doc.on.doc") { copyTab }
            Tab("Reserve", systemImage: "calendar.badge.plus") { reserveTab }
        }
        .frame(width: 560, height: 620)
    }

    private var calendarsTab: some View {
        Form {
            Section {
                Text("Checked calendars are shown and count as busy. Same as the checkboxes in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if store.sources.isEmpty {
                Text("No calendars available. Grant Calendar access first.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.sources) { source in
                Section(source.title) {
                    ForEach(source.calendars) { calendar in
                        Toggle(isOn: Binding(
                            get: { prefs.countsAsBusy(calendarID: calendar.id) },
                            set: { prefs.setCountsAsBusy($0, calendarID: calendar.id) }
                        )) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Circle().fill(calendar.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }
            Section {
                Toggle("All-day events count as busy", isOn: $prefs.allDayCountsAsBusy)
            } footer: {
                Text("Events marked as “free” and invitations you declined never count as busy.")
            }
        }
        .formStyle(.grouped)
    }

    private var weekTab: some View {
        Form {
            Section("Working hours") {
                DatePicker("Start", selection: timeBinding(\.workStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: timeBinding(\.workEndMinutes), displayedComponents: .hourAndMinute)
            }
            Section {
                Toggle("Show weekends", isOn: $prefs.showWeekends)
            }
            Section {
                Toggle("Show icon in menu bar", isOn: $prefs.showMenuBarIcon)
            } footer: {
                Text("Quick access to copy, reserve and open Pin-Cal from the menu bar.")
            }
        }
        .formStyle(.grouped)
    }

    private var copyTab: some View {
        Form {
            Section {
                Picker("Default language", selection: $prefs.defaultLanguage) {
                    ForEach(CopyLanguage.allCases) { Text($0.nativeName).tag($0) }
                }
                Toggle("Write my own message", isOn: $prefs.useCustomMessage)
            }

            if prefs.useCustomMessage {
                Section {
                    Picker("Message for", selection: $editLanguage) {
                        ForEach(CopyLanguage.allCases) { Text($0.shortName).tag($0).help($0.nativeName) }
                    }
                    .pickerStyle(.segmented)
                    TextEditor(text: Binding(
                        get: { prefs.template(for: editLanguage) },
                        set: { prefs.setTemplate($0, for: editLanguage) }
                    ))
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    HStack {
                        Text("Each language has its own message; the one matching the language you copy in is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset to Example") { prefs.setTemplate(editLanguage.defaultTemplate, for: editLanguage) }
                    }
                } header: {
                    Text("Your message")
                }

                Section("How to write your message") {
                    VStack(alignment: .leading, spacing: 6) {
                        helpRow("{slots}", "The selected times, as a list per day. Added at the end if you leave it out.")
                        helpRow("{count}", "Number of selected slots, e.g. “3”.")
                        helpRow("{timezone}", "Your time zone, e.g. “CET”.")
                        Divider().padding(.vertical, 2)
                        helpRow("**bold**", "Bold text")
                        helpRow("*italic*", "Italic text (or _italic_)")
                        helpRow("[text](https://…)", "A link")
                        helpRow("- item", "A list item")
                        helpRow("empty line", "Starts a new paragraph")
                        Text("Mail, Outlook and other rich-text apps get the formatting; plain-text fields get the same text without the symbols.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            } else {
                Section {
                    Toggle("Start with an intro line", isOn: $prefs.includeIntro)
                    Toggle("Mention the time zone", isOn: $prefs.includeTimeZone)
                }
            }

            Section("Preview") {
                Text(richPreview)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear { editLanguage = prefs.defaultLanguage }
    }

    private func helpRow(_ syntax: String, _ meaning: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(syntax)
                .font(.callout.monospaced())
                .frame(width: 150, alignment: .leading)
                .textSelection(.enabled)
            Text(meaning)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var previewFormatter: AvailabilityFormatter {
        let language = prefs.useCustomMessage ? editLanguage : prefs.defaultLanguage
        return AvailabilityFormatter(
            language: language,
            includeIntro: prefs.includeIntro,
            includeTimeZone: prefs.includeTimeZone,
            template: prefs.useCustomMessage ? prefs.template(for: language) : nil
        )
    }

    private var previewSlots: [DateInterval] {
        let calendar = Calendar.autoupdatingCurrent
        let tomorrow = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow
        func at(_ day: Date, _ h: Int, _ m: Int) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
        return [
            DateInterval(start: at(tomorrow, 10, 0), end: at(tomorrow, 11, 0)),
            DateInterval(start: at(tomorrow, 14, 0), end: at(tomorrow, 15, 30)),
            DateInterval(start: at(dayAfter, 9, 0), end: at(dayAfter, 10, 0)),
        ]
    }

    /// Renders the HTML that gets pasted, so the preview matches Mail.
    private var richPreview: AttributedString {
        let formatter = previewFormatter
        let html = "<div style=\"font-family: -apple-system; font-size: 13px\">\(formatter.html(previewSlots))</div>"
        guard let data = html.data(using: .utf8),
              let ns = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                  documentAttributes: nil
              ),
              var result = try? AttributedString(ns, including: \.appKit)
        else { return AttributedString(formatter.plainText(previewSlots)) }
        // Drop HTML's fixed black so the preview follows light/dark mode.
        for run in result.runs where run.link == nil {
            result[run.range].appKit.foregroundColor = nil
        }
        while result.characters.last?.isNewline == true { result.characters.removeLast() }
        return result
    }

    private var reserveTab: some View {
        Form {
            Section {
                Text("“Reserve” adds the selected slots as busy events, so nothing else gets planned there while you wait for an answer. Click a reservation (striped) in Pin-Cal to release it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Calendar", selection: $prefs.holdCalendarID) {
                    Text("Pin-Cal (created automatically)").tag(String?.none)
                    ForEach(store.sources) { source in
                        let writable = source.calendars.filter(\.isWritable)
                        if !writable.isEmpty {
                            Section(source.title) {
                                ForEach(writable) { calendar in
                                    Text(calendar.title).tag(Optional(calendar.id))
                                }
                            }
                        }
                    }
                }
                TextField("Event title", text: $prefs.holdTitle, prompt: Text("Voorlopig"))
            }
        }
        .formStyle(.grouped)
    }

    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = prefs[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                prefs[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
