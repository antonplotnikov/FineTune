import Foundation

/// Undo/redo for EQ edits. Rapid consecutive changes (a slider drag) collapse into one step.
nonisolated struct EQEditHistory {
    private(set) var undoStack: [EQSettings] = []
    private(set) var redoStack: [EQSettings] = []
    private var lastChange: Date?

    let limit: Int
    let coalesceInterval: TimeInterval

    init(limit: Int = 50, coalesceInterval: TimeInterval = 0.6) {
        self.limit = limit
        self.coalesceInterval = coalesceInterval
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Call after a user edit, passing the value from *before* the edit.
    mutating func record(previous: EQSettings, now: Date = Date()) {
        defer { lastChange = now }
        redoStack.removeAll()
        if let lastChange, now.timeIntervalSince(lastChange) < coalesceInterval { return }
        undoStack.append(previous)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
    }

    mutating func undo(current: EQSettings) -> EQSettings? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        lastChange = nil
        return previous
    }

    mutating func redo(current: EQSettings) -> EQSettings? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        lastChange = nil
        return next
    }

    mutating func clear() {
        undoStack.removeAll(); redoStack.removeAll(); lastChange = nil
    }
}

/// A/B comparison of two EQ curves: edit one while the other is kept aside, flip to compare by ear.
nonisolated struct EQABCompare {
    enum Slot: String { case a = "A", b = "B" }

    private(set) var isActive = false
    private(set) var activeSlot: Slot = .b
    private var slotA = EQSettings()
    private var slotB = EQSettings()

    /// Starts comparing: A keeps the current curve, edits continue on B.
    mutating func begin(current: EQSettings) {
        slotA = current; slotB = current
        activeSlot = .b
        isActive = true
    }

    /// Keeps the active slot in sync with edits made while comparing.
    mutating func store(current: EQSettings) {
        guard isActive else { return }
        if activeSlot == .a { slotA = current } else { slotB = current }
    }

    /// Switches slot and returns the curve to apply.
    mutating func toggle(current: EQSettings) -> EQSettings {
        guard isActive else { return current }
        store(current: current)
        activeSlot = activeSlot == .a ? .b : .a
        return activeSlot == .a ? slotA : slotB
    }

    mutating func end() { isActive = false }
}

extension EQSettings {
    /// JSON text for the system clipboard, so a curve can be pasted onto another app or tab.
    var clipboardString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Parses clipboard text; returns nil unless it looks like an EQ curve.
    static func fromClipboard(_ text: String) -> EQSettings? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["bandGains"] != nil || object["parametricBands"] != nil
        else { return nil }
        return try? JSONDecoder().decode(EQSettings.self, from: data)
    }
}
