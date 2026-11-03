import PinCalCore
import SwiftUI

struct ContentView: View {
    let store: CalendarStore
    @Bindable var model: PickerModel
    @Bindable var prefs: Preferences
    @State private var copyMonitor = CopyShortcutMonitor()

    var body: some View {
        Group {
            switch store.access {
            case .granted:
                NavigationSplitView {
                    CalendarSidebar(store: store, model: model, prefs: prefs)
                        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
                } detail: {
                    WeekView(store: store, model: model, prefs: prefs)
                }
            case .denied:
                ContentUnavailableView {
                    Label("No access to Calendar", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Pin-Cal needs full calendar access to see when you're busy. It only adds or removes events when you reserve or release slots.")
                } actions: {
                    Button("Open Privacy Settings") { store.openPrivacySettings() }
                        .buttonStyle(.borderedProminent)
                }
            case .unknown:
                ProgressView()
            }
        }
        .task { await store.requestAccessIfNeeded() }
        .task(id: model.weekStart) { store.load(model.weekRange) }
        .navigationTitle(model.weekTitle)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect()
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.toast)
        .alert("Couldn't update Calendar", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            copyMonitor.install { [model, prefs] in model.copy(using: prefs) }
        }
        .onDisappear { copyMonitor.uninstall() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.moveWeek(by: -1) } label: { Label("Previous Week", systemImage: "chevron.left") }
            Button("Today") { model.goToToday() }
                .disabled(model.isCurrentWeek)
            Button { model.moveWeek(by: 1) } label: { Label("Next Week", systemImage: "chevron.right") }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Click to place", selection: $prefs.slotMinutes) {
                Text("Drag only").tag(0)
                Divider()
                ForEach([15, 30, 45, 60, 90], id: \.self) { Text("Click: \($0) min").tag($0) }
            }
            .pickerStyle(.menu)
            .help("Drag over free time to select it. Pick a length to place a fixed slot with one click.")

            Picker("Language", selection: $model.language) {
                ForEach(CopyLanguage.allCases) { Text($0.shortName).tag($0).help($0.nativeName) }
            }
            .pickerStyle(.segmented)
            .help("Language of the copied text")

            Button { model.proposals.removeAll() } label: { Label("Clear", systemImage: "xmark.circle") }
                .disabled(model.proposals.isEmpty)
                .help("Clear selection")

            Button { model.reserve(store: store, prefs: prefs) } label: {
                Label("Reserve", systemImage: "calendar.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.proposals.isEmpty)
            .help("Reserve the selected slots as “\(prefs.holdTitle)” in your reservation calendar (⌘R)")

            Button { model.copy(using: prefs) } label: {
                Label(model.proposals.isEmpty ? "Copy" : "Copy (\(model.proposals.count))", systemImage: "doc.on.doc")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.proposals.isEmpty)
            .help("Copy selected slots as text (⌘C)")
        }
    }
}
