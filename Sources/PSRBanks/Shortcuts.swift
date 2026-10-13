import SwiftUI
import PSRCore

/// Save-panel flow shared by the Export button and the ⌘E command.
@MainActor
enum ExportAction {
    static func run(_ setlistID: UUID, store: LibraryStore) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "USER001.USR"
        panel.message = "Save a PSR-E483 user file. Copy it to the USB stick and load it from the keyboard."
        panel.allowedContentTypes = [.data]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.export(setlistID: setlistID, to: url) } catch { store.lastError = error.localizedDescription }
    }
}

/// Copy/paste of patches goes through the system pasteboard as text, so it also survives switching setlists.
enum PatchClipboard {
    static func copy(_ id: UUID) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(DragItem.patch(id).payload, forType: .string)
    }
    /// The patch currently on the pasteboard, if the pasteboard holds one.
    static func pasted() -> UUID? {
        guard let s = NSPasteboard.general.string(forType: .string), case .patch(let id)? = DragItem(payload: s) else { return nil }
        return id
    }
}

/// Cheat sheet opened with ⌘/ (Help ▸ Keyboard Shortcuts).
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let groups: [(String, [(String, String)])] = [
        ("Library", [("⌘O", "Import a USR file"), ("⌘N", "New setlist"), ("⌘E", "Export the open setlist"), ("⌘D", "Duplicate the open setlist"),
                     ("⌘F", "Search"), ("⌘1", "Patches"), ("⌘2 … ⌘9", "Open setlist 1 … 8 (in sidebar order)")]),
        ("Selected patch (slot in a setlist, or row in the patch list)", [("⌘I", "Show info"), ("⌘R", "Rename in place"), ("⌘T", "Edit tags"), ("⌘⌫", "Empty the slot (setlist only)"),
                     ("⇧⌘R", "Rename the open setlist")]),
        ("Copy, paste and default patch", [("⌘C / ⌘X", "Copy / cut the selected patch (slot or list row)"), ("⌘V", "Paste it into the selected slot"),
                     ("⇧⌘D", "Mark the selected patch as the default patch"), ("⇧⌘U", "Put the default patch into the selected slot"),
                     ("⇧⌘F", "Fill all empty slots with the default patch")]),
        ("Renaming (patches, slots and setlists)", [("Click a selected name", "Edit it in place, like Finder"), ("Double-click a name", "Edit it right away"), ("Return", "Save the new name (or start editing a selected item)"),
                     ("Esc", "Cancel"), ("Click elsewhere", "Save")]),
        ("Patch list", [("↑ ↓", "Move the selection")]),
        ("Setlist grid (click a slot first)", [("← →", "Previous / next memory"), ("↑ ↓", "Previous / next bank"), ("⌫", "Put the default patch in the slot (asks first if no default is set)"), ("Return", "Rename the patch"), ("Space", "Show the patch info"),
                     ("Double-click a patch", "Put it in the selected slot and move on")]),
        ("Setlist grid (click a bank name first)", [("↑ ↓", "Previous / next bank"), ("→", "Go to the bank's first memory"), ("⌫", "Delete the bank (asks first)"), ("Space", "Show the bank info")]),
        ("Windows", [("⌘/", "This list (the app version is at the bottom of the sidebar)"), ("⌘W", "Close window"), ("⌘Q", "Quit")]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) { LogoMark(size: 34); Text("Keyboard shortcuts").font(.system(size: 20, weight: .bold, design: .rounded)) }
                    ForEach(groups, id: \.0) { title, rows in
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title).font(.headline)
                                ForEach(rows, id: \.0) { key, what in
                                    HStack {
                                        Text(key).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Theme.well, in: RoundedRectangle(cornerRadius: 6))
                                            .frame(minWidth: 130, alignment: .leading)
                                        Text(what).foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(20)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(14)
        }
        .frame(width: 560, height: 600)
        .background(Theme.canvas)
    }
}
