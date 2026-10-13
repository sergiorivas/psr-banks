import SwiftUI
import PSRCore

/// Basic properties of one bank (a row of 4 memories) of a setlist, and where it is stored.
struct BankInfoSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let setlistID: UUID
    let bank: Int

    var body: some View {
        VStack(spacing: 0) {
            if let s = store.setlist(setlistID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.bankHues[bank - 1]).frame(width: 12, height: 12)
                            Text("Bank \(bank)").font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        properties(s)
                        memories(s)
                    }.padding(20)
                }
            } else {
                Text("This setlist no longer exists.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(14)
        }
        .frame(width: 640, height: 520)
        .background(Theme.canvas)
    }

    private func properties(_ s: SetlistMeta) -> some View {
        let filled = (1...SlotLayout.memories).filter { store.patch(s.slots[SlotLayout.position(bank: bank, memory: $0)]) != nil }.count
        let folder = store.setlistFolderURL(s.id)
        return section("Properties") {
            row("Setlist", s.name)
            row("Description", s.bankDescriptions[bank - 1].isEmpty ? "—" : s.bankDescriptions[bank - 1])
            row("Memories filled", "\(filled) of \(SlotLayout.memories)")
            row("File", folder.appendingPathComponent("setlist.json").path, mono: true)
            HStack {
                Spacer().frame(width: 142)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("setlist.json")]) }
                    .controlSize(.small)
            }
            Text("A bank is not a file of its own: it is stored inside its setlist’s file together with the other seven banks, and ends up in the .USR you export.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func memories(_ s: SetlistMeta) -> some View {
        section("Memories") {
            ForEach(1...SlotLayout.memories, id: \.self) { m in
                let pos = SlotLayout.position(bank: bank, memory: m)
                if let p = store.patch(s.slots[pos]) {
                    row("Memory \(m)", "\(p.name) · \(p.meta.mainVoice) \(VoiceCatalog.name(for: p.meta.mainVoice))"
                        + (p.meta.splitOn ? " · split" : "") + (p.meta.dualOn ? " · dual" : ""))
                    row("", store.patchFolderURL(p.id).path, mono: true)
                } else {
                    row("Memory \(m)", s.slots[pos] == nil ? "Empty" : "Missing patch (its file was deleted)")
                }
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
