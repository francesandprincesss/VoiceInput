import Foundation

@MainActor
protocol HistoryStoring: AnyObject {
    func add(text: String)
}

@MainActor
final class HistoryStore: ObservableObject, HistoryStoring {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var persistenceError: String?

    private let storageURL: URL?

    init(storageURL: URL? = HistoryStore.defaultStorageURL()) {
        self.storageURL = storageURL
        load()
    }

    func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        persist()
    }

    func add(text: String) {
        add(HistoryEntry(text: text))
    }

    func delete(id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            entries = try JSONDecoder().decode(
                [HistoryEntry].self,
                from: Data(contentsOf: storageURL)
            )
        } catch {
            persistenceError = "History could not be loaded: \(error.localizedDescription)"
        }
    }

    private func persist() {
        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storageURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "History could not be saved: \(error.localizedDescription)"
        }
    }

    nonisolated private static func defaultStorageURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }
}
