import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    private let copier: HistoryEntryCopier

    @State private var copiedEntryID: HistoryEntry.ID?
    @State private var feedbackTask: Task<Void, Never>?

    init(
        store: HistoryStore,
        clipboard: any HistoryClipboardWriting = SystemHistoryClipboard()
    ) {
        self.store = store
        copier = HistoryEntryCopier(clipboard: clipboard)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if store.entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("No History Yet")
                            .font(.title3.weight(.semibold))
                        Text("Your local transcriptions will appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.entries) { entry in
                        HistoryRow(
                            entry: entry,
                            showsCopiedFeedback: copiedEntryID == entry.id,
                            copyAction: { copy(entry) }
                        )
                        .contextMenu {
                            Button("Copy") {
                                copy(entry)
                            }
                            Button("Delete", role: .destructive) {
                                store.delete(id: entry.id)
                                if copiedEntryID == entry.id {
                                    feedbackTask?.cancel()
                                    copiedEntryID = nil
                                }
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                    }
                    .listStyle(.plain)
                }
            }

            Divider()

            HStack {
                if let error = store.persistenceError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Clear", role: .destructive) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 500, minHeight: 380)
        .onDisappear {
            feedbackTask?.cancel()
        }
    }

    private func copy(_ entry: HistoryEntry) {
        guard copier.copy(entry) else { return }
        feedbackTask?.cancel()
        copiedEntryID = entry.id
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, copiedEntryID == entry.id else { return }
            copiedEntryID = nil
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let showsCopiedFeedback: Bool
    let copyAction: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: copyAction) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.text)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                    Text(entry.createdAt, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if showsCopiedFeedback {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .animation(.easeOut(duration: 0.15), value: showsCopiedFeedback)
    }
}
