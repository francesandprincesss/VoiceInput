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
