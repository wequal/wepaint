import Foundation

struct HistoryEntry {
    let label: String
    let undo: () -> Void
    let redo: () -> Void
}

/// Undo/redo stack with a bounded number of entries.
@Observable
final class HistoryManager {
    private(set) var undoStack: [HistoryEntry] = []
    private(set) var redoStack: [HistoryEntry] = []
    var limit: Int = 40

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoLabel: String? { undoStack.last?.label }
    var redoLabel: String? { redoStack.last?.label }

    func push(_ entry: HistoryEntry) {
        undoStack.append(entry)
        redoStack.removeAll()
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
    }

    func push(label: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        push(HistoryEntry(label: label, undo: undo, redo: redo))
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        entry.undo()
        redoStack.append(entry)
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        entry.redo()
        undoStack.append(entry)
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
