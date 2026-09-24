import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

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
                        Text("Transcribed text will appear here in a future version.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.text)
                            Text(entry.createdAt, format: .dateTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button("Delete") {
                                store.delete(id: entry.id)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Clear", role: .destructive) {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
            .padding(10)
        }
        .frame(minWidth: 500, minHeight: 380)
    }
}
