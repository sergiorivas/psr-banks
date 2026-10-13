import SwiftUI
import PSRCore

/// Basic properties of a setlist, where it is stored, and what its 8 banks hold.
struct SetlistInfoSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let setlistID: UUID

    var body: some View {
        VStack(spacing: 0) {
            if let s = store.setlist(setlistID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(s.name).font(.system(size: 20, weight: .bold, design: .rounded))
                        properties(s)
                        banks(s)
                    }.padding(20)
                }
            } else {
                Text("This setlist no longer exists.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(14)
        }
        .frame(width: 640, height: 640)
        .background(Theme.canvas)
    }

    private func properties(_ s: SetlistMeta) -> some View {
        let file = store.setlistFolderURL(s.id).appendingPathComponent("setlist.json")
        let missing = store.missingCount(s)
        return section("Properties") {
            row("Name", s.name)
            row("Slots filled", "\(store.filledCount(s)) of 32" + (missing > 0 ? " · \(missing) missing from the library" : ""))
            row("Ready to export", store.isComplete(s) ? "Yes" : "No, fill all 32 slots first")
            row("Tags", s.tags.isEmpty ? "—" : s.tags.map { "#\($0)" }.joined(separator: "  "))
            row("Created", s.createdAt.formatted(date: .abbreviated, time: .shortened))
            row("File", file.path, mono: true)
            HStack {
                Spacer().frame(width: 142)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.controlSize(.small)
            }
        }
    }

    private func banks(_ s: SetlistMeta) -> some View {
        section("Banks") {
            ForEach(1...SlotLayout.banks, id: \.self) { bank in
                let names = (1...SlotLayout.memories).map { m in
                    store.patch(s.slots[SlotLayout.position(bank: bank, memory: m)])?.name
                        ?? (s.slots[SlotLayout.position(bank: bank, memory: m)] == nil ? "empty" : "missing")
                }
                let label = s.bankDescriptions[bank - 1]
                row("Bank \(bank)", (label.isEmpty ? "" : "\(label) — ") + names.joined(separator: " · "))
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13)).textSelection(.enabled)
            Spacer(minLength: 0)
        }.font(.system(size: 13))
    }
}
