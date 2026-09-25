import Foundation
import Testing
@testable import VoiceInput

@Test("History persists text and timestamp as JSON")
@MainActor
func historyPersistence() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceInputHistoryTests-\(UUID().uuidString)", isDirectory: true)
    let file = directory.appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: directory) }

    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let entry = HistoryEntry(text: "Привет, world", createdAt: timestamp)
    let firstStore = HistoryStore(storageURL: file)
    firstStore.add(entry)
    #expect(firstStore.persistenceError == nil)

    let reloadedStore = HistoryStore(storageURL: file)
    #expect(reloadedStore.entries == [entry])
}

@Test("Copying a History entry writes its complete text")
@MainActor
func historyEntryCopyUsesCompleteText() {
    let clipboard = HistoryClipboardMock()
    let copier = HistoryEntryCopier(clipboard: clipboard)
    let fullText = "First line\nSecond line that would be outside a truncated UI preview"

    #expect(copier.copy(HistoryEntry(text: fullText)))
    #expect(clipboard.values == [fullText])
}

@Test("Russian Unicode is copied without changes")
@MainActor
func historyEntryCopyPreservesUnicode() {
    let clipboard = HistoryClipboardMock()
    let copier = HistoryEntryCopier(clipboard: clipboard)
    let text = "Привет, это проверка голосового ввода — ёжик 🦔"

    #expect(copier.copy(HistoryEntry(text: text)))
    #expect(clipboard.values.first == text)
}

@Test("Deleting one entry persists the deletion and preserves the others")
@MainActor
func deletingOneHistoryEntryPersists() throws {
    let location = makeHistoryTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let deleted = HistoryEntry(text: "delete me")
    let retainedA = HistoryEntry(text: "keep one")
    let retainedB = HistoryEntry(text: "keep two")
    let store = HistoryStore(storageURL: location.file)
    store.add(retainedA)
    store.add(deleted)
    store.add(retainedB)

    store.delete(id: deleted.id)

    #expect(store.entries == [retainedB, retainedA])
    let reloaded = HistoryStore(storageURL: location.file)
    #expect(reloaded.entries == [retainedB, retainedA])
    #expect(!reloaded.entries.contains { $0.id == deleted.id })
}

@Test("Clear History persists an empty collection")
@MainActor
func clearingHistoryPersists() throws {
    let location = makeHistoryTestLocation()
    defer { try? FileManager.default.removeItem(at: location.directory) }
    let store = HistoryStore(storageURL: location.file)
    store.add(text: "one")
    store.add(text: "two")

    store.clear()

    #expect(store.entries.isEmpty)
    #expect(HistoryStore(storageURL: location.file).entries.isEmpty)
}

private final class HistoryClipboardMock: HistoryClipboardWriting {
    var values: [String] = []

    func write(_ text: String) -> Bool {
        values.append(text)
        return true
    }
}

private func makeHistoryTestLocation() -> (directory: URL, file: URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceInputHistoryTests-\(UUID().uuidString)", isDirectory: true)
    return (directory, directory.appendingPathComponent("history.json"))
}
