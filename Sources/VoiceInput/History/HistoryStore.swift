import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
    }

    func add(text: String) {
        add(HistoryEntry(text: text))
    }

    func delete(id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    func clear() {
        entries.removeAll()
    }
}
