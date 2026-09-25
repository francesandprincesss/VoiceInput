import AppKit

@MainActor
protocol HistoryClipboardWriting: AnyObject {
    @discardableResult
    func write(_ text: String) -> Bool
}

@MainActor
final class SystemHistoryClipboard: HistoryClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func write(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor
struct HistoryEntryCopier {
    let clipboard: any HistoryClipboardWriting

    @discardableResult
    func copy(_ entry: HistoryEntry) -> Bool {
        clipboard.write(entry.text)
    }
}
