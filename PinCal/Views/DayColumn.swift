import PinCalCore
import SwiftUI

/// One day in the week grid: background, events (read-only) and selectable proposal slots.
struct DayColumn: View {
    let day: Date
    let events: [DisplayEvent]
    let busy: [DateInterval]
    @Bindable var model: PickerModel
    let store: CalendarStore
    let prefs: Preferences
    let hourHeight: CGFloat

    @State private var draft: DateInterval?
    @State private var releaseTarget: DisplayEvent?

    private var calendar: Calendar { model.calendar }
    private var spaceName: String { "day-\(day.timeIntervalSinceReferenceDate)" }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                background
                    .contentShape(.rect)
                    .gesture(selectGesture)

                eventsLayer(width: width)

                if calendar.isDateInToday(day) {
                    nowLine(width: width)
                }

                if let draft {
                    let top = y(draft.start)
                    slotShape(draft, isDraft: true)
                        .frame(width: width - 6, height: max(y(draft.end) - top, 8))
                        .offset(x: 3, y: top)
                        .allowsHitTesting(false)
                }

                ForEach(proposalsToday) { proposal in
                    proposalView(proposal, width: width)
                }
            }
            .coordinateSpace(.named(spaceName))
        }
    }

    // MARK: Geometry

    private func y(_ date: Date) -> CGFloat {
        CGFloat(TimeGrid.minutes(of: date, inDayStarting: day, calendar: calendar)) / 60 * hourHeight
    }

    private func minutes(atY y: CGFloat) -> Double { Double(y / hourHeight * 60) }

    private func date(atMinutes m: Int) -> Date { TimeGrid.date(atMinutes: m, inDayStarting: day, calendar: calendar) }

    private func interval(_ startMinutes: Int, _ endMinutes: Int) -> DateInterval {
        DateInterval(start: date(atMinutes: startMinutes), end: date(atMinutes: endMinutes))
    }

    private var proposalsToday: [Proposal] {
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return model.proposals.items.filter { $0.interval.start >= day && $0.interval.start < next }
    }

    // MARK: Selecting

    private var selectGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(spaceName))
            .onChanged { value in
                guard abs(value.translation.height) >= 4 else {
                    draft = nil
                    return
                }
                let a = minutes(atY: min(value.startLocation.y, value.location.y))
                let b = minutes(atY: max(value.startLocation.y, value.location.y))
                let start = min(TimeGrid.snap(a, rule: .down), TimeGrid.minutesPerDay - 15)
                let end = max(TimeGrid.snap(b, rule: .up), start + 15)
                draft = interval(start, end)
            }
            .onEnded { value in
                if let draft {
                    model.proposals.add(draft)
                    self.draft = nil
                } else if prefs.slotMinutes > 0 {
                    let start = min(TimeGrid.snap(minutes(atY: value.startLocation.y), rule: .down),
                                    TimeGrid.minutesPerDay - prefs.slotMinutes)
                    model.proposals.add(interval(start, start + prefs.slotMinutes))
                }
            }
    }

    private func resizeGesture(_ proposal: Proposal, edge: VerticalEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(spaceName))
            .onChanged { value in
                guard let current = model.proposals.proposal(id: proposal.id) else { return }
                let startM = Int(TimeGrid.minutes(of: current.interval.start, inDayStarting: day, calendar: calendar))
                let endM = Int(TimeGrid.minutes(of: current.interval.end, inDayStarting: day, calendar: calendar))
                let m = TimeGrid.snap(minutes(atY: value.location.y))
                let updated = edge == .top
                    ? interval(min(m, endM - 15), endM)
                    : interval(startM, max(m, startM + 15))
                model.proposals.update(id: proposal.id, to: updated)
            }
            .onEnded { _ in model.proposals.normalize(id: proposal.id) }
    }

    // MARK: Layers

    private var background: some View {
        Canvas { context, size in
            let shade = Color.primary.opacity(0.045)
            let workTop = CGFloat(prefs.workStartMinutes) / 60 * hourHeight
            let workBottom = CGFloat(prefs.workEndMinutes) / 60 * hourHeight
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: workTop)), with: .color(shade))
            context.fill(Path(CGRect(x: 0, y: workBottom, width: size.width, height: size.height - workBottom)), with: .color(shade))
            if calendar.isDateInWeekend(day) {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(shade))
            }
            var lines = Path()
            for hour in 1..<24 {
                let y = CGFloat(hour) * hourHeight
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(lines, with: .color(.primary.opacity(0.1)), lineWidth: 0.5)
        }
    }

    private func eventsLayer(width: CGFloat) -> some View {
        let placements = ColumnLayout.layout(events.map(\.interval))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(events, placements)), id: \.0.id) { event, placement in
                let columnWidth = (width - 6) / CGFloat(placement.columnCount)
                let top = y(event.start)
                let height = max(y(event.end) - top, 14)
                EventBlock(event: event, countsAsBusy: BusyCalculator.countsAsBusy(event.info, rules: prefs.busyRules))
                    .frame(width: max(columnWidth - 1, 1), height: height)
                    .contentShape(.rect)
                    .onTapGesture { releaseTarget = event }
                    .popover(isPresented: Binding(
                        get: { releaseTarget?.id == event.id },
                        set: { if !$0 { releaseTarget = nil } }
                    )) { releasePopover(event) }
                    .help("Reservation · click to release")
                    .allowsHitTesting(event.isHold)
                    .offset(x: 1 + CGFloat(placement.column) * columnWidth, y: top)
            }
        }
    }

    private func releasePopover(_ event: DisplayEvent) -> some View {
        let siblings = store.holdSiblings(of: event).count
        return VStack(alignment: .leading, spacing: 10) {
            Text(event.title).font(.headline)
            Text("\(event.start.formatted(date: .abbreviated, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Release", role: .destructive) {
                    releaseTarget = nil
                    model.release([event], store: store)
                }
                if siblings > 1 {
                    Button("Release whole batch") {
                        releaseTarget = nil
                        model.releaseGroup(of: event, store: store)
                    }
                    .help("Releases every slot reserved together with this one")
                }
            }
        }
        .padding(14)
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.everyMinute) { context in
            Rectangle()
                .fill(.red)
                .frame(width: width, height: 1.5)
                .offset(y: y(context.date))
                .allowsHitTesting(false)
        }
    }

    private func proposalView(_ proposal: Proposal, width: CGFloat) -> some View {
        let top = y(proposal.interval.start)
        let height = max(y(proposal.interval.end) - top, 8)
        return slotShape(proposal.interval, isDraft: false)
            .contentShape(.rect)
            .onTapGesture { model.proposals.remove(id: proposal.id) }
            .help("Click to remove · drag the top or bottom edge to resize")
            .overlay(alignment: .top) { resizeHandle(proposal, edge: .top) }
            .overlay(alignment: .bottom) { resizeHandle(proposal, edge: .bottom) }
            .frame(width: width - 6, height: height)
            .offset(x: 3, y: top)
    }

    private func resizeHandle(_ proposal: Proposal, edge: VerticalEdge) -> some View {
        Color.clear
            .frame(height: 7)
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: edge == .top ? .top : .bottom))
            .gesture(resizeGesture(proposal, edge: edge))
    }

    private func slotShape(_ interval: DateInterval, isDraft: Bool) -> some View {
        let conflict = BusyCalculator.overlapsBusy(interval, busy: busy)
        let tint: Color = conflict ? .orange : .accentColor
        let top = y(interval.start)
        let height = max(y(interval.end) - top, 8)
        let label = "\(interval.start.formatted(date: .omitted, time: .shortened))–\(interval.end.formatted(date: .omitted, time: .shortened))"

        return RoundedRectangle(cornerRadius: 6)
            .fill(tint.opacity(isDraft ? 0.18 : 0.28))
            .strokeBorder(tint, style: StrokeStyle(lineWidth: 1.5, dash: isDraft ? [4, 3] : []))
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).font(.caption.weight(.semibold).monospacedDigit())
                    if conflict && height > 30 {
                        Text("Overlaps an event").font(.caption2)
                    }
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.top, 2)
            }
            .clipped()
    }
}

struct EventBlock: View {
    let event: DisplayEvent
    let countsAsBusy: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.caption.weight(.medium))
                    .strikethrough(event.info.isDeclined)
                Text(event.start, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(event.color.opacity(countsAsBusy ? 0.22 : 0.08))
        .background { if event.isHold { Hatch(color: event.color) } }
        .overlay {
            if event.isHold {
                RoundedRectangle(cornerRadius: 4).strokeBorder(event.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(.rect(cornerRadius: 4))
        .opacity(countsAsBusy ? 1 : 0.5)
    }
}

/// Diagonal stripes marking reservations made by Pin-Cal.
struct Hatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1.5)
        }
    }
}
