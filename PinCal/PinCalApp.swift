import AppKit
import SwiftUI

@main
struct PinCalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var prefs: Preferences
    @State private var store = CalendarStore()
    @State private var model: PickerModel

    init() {
        let prefs = Preferences()
        _prefs = State(initialValue: prefs)
        _model = State(initialValue: PickerModel(language: prefs.defaultLanguage))
    }

    var body: some Scene {
        Window("Pin-Cal", id: "main") {
            ContentView(store: store, model: model, prefs: prefs)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            // The standard Edit menu stays intact so text fields (Settings) keep working.
            // ⌘C in the main window is handled by `CopyShortcutMonitor`.
            CommandMenu("Selection") {
                Button("Copy Availability") { model.copy(using: prefs) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Reserve in Calendar") { model.reserve(store: store, prefs: prefs) }
                    .keyboardShortcut("r")
                Divider()
                Button("Clear Selection") { model.proposals.removeAll() }
                    .keyboardShortcut(.delete)
            }
            CommandMenu("Go") {
                Button("Previous Week") { model.moveWeek(by: -1) }
                    .keyboardShortcut(.leftArrow)
                Button("Next Week") { model.moveWeek(by: 1) }
                    .keyboardShortcut(.rightArrow)
                Button("Today") { model.goToToday() }
                    .keyboardShortcut("t")
            }
        }

        Settings {
            SettingsView(store: store, prefs: prefs)
        }

        MenuBarExtra("Pin-Cal", systemImage: "pin.fill", isInserted: $prefs.showMenuBarIcon) {
            MenuBarMenu(store: store, model: model, prefs: prefs)
        }
    }
}

private struct MenuBarMenu: View {
    let store: CalendarStore
    let model: PickerModel
    let prefs: Preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Pin-Cal") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Divider()
        let n = model.proposals.count
        Button(n == 0 ? "Copy Availability" : "Copy Availability (\(n))") { model.copy(using: prefs) }
            .disabled(n == 0)
        Button("Reserve in Calendar") { model.reserve(store: store, prefs: prefs) }
            .disabled(n == 0)
        Button("Clear Selection") { model.proposals.removeAll() }
            .disabled(n == 0)
        Divider()
        Button("Settings…") {
            openSettings()
            NSApp.activate()
        }
        Button("Quit Pin-Cal") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep running in the Dock when the window is closed; clicking the Dock icon reopens it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Makes plain ⌘C copy the selected slots whenever the week window is key and no text field is editing.
@MainActor
final class CopyShortcutMonitor {
    private var monitor: Any?

    func install(onCopy: @escaping @MainActor () -> Bool) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "c",
                  let window = event.window,
                  !(window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false),
                  !(window.firstResponder is NSText)
            else { return event }
            let handled = MainActor.assumeIsolated { onCopy() }
            return handled ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
