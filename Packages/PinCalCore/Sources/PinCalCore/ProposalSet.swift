import Foundation

public struct Proposal: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var interval: DateInterval

    public init(id: UUID = UUID(), interval: DateInterval) {
        self.id = id
        self.interval = interval
    }
}

/// The time slots the user has selected to offer. Kept sorted; overlapping or
/// touching slots are merged when added.
public struct ProposalSet: Sendable, Equatable {
    public private(set) var items: [Proposal] = []

    public init() {}

    public var intervals: [DateInterval] { items.map(\.interval) }
    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public func proposal(id: UUID) -> Proposal? { items.first { $0.id == id } }

    /// Adds a slot, merging it with any overlapping or touching slots. Returns the id of the resulting slot.
    @discardableResult
    public mutating func add(_ interval: DateInterval, preferredID: UUID? = nil) -> UUID {
        guard interval.duration > 0 else { return preferredID ?? UUID() }
        var merged = interval
        var keptID = preferredID
        var remaining: [Proposal] = []
        for item in items {
            if item.interval.start <= merged.end && merged.start <= item.interval.end {
                merged = DateInterval(start: min(merged.start, item.interval.start),
                                      end: max(merged.end, item.interval.end))
                keptID = keptID ?? item.id
            } else {
                remaining.append(item)
            }
        }
        let id = keptID ?? UUID()
        remaining.append(Proposal(id: id, interval: merged))
        items = remaining.sorted { $0.interval.start < $1.interval.start }
        return id
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    /// Changes a slot in place without merging (used during a live resize).
    public mutating func update(id: UUID, to interval: DateInterval) {
        guard let index = items.firstIndex(where: { $0.id == id }), interval.duration > 0 else { return }
        items[index].interval = interval
        items.sort { $0.interval.start < $1.interval.start }
    }

    /// Re-merges a slot with its neighbours (call when a resize ends).
    public mutating func normalize(id: UUID) {
        guard let item = proposal(id: id) else { return }
        remove(id: id)
        add(item.interval, preferredID: id)
    }

    public mutating func removeAll() {
        items.removeAll()
    }
}
