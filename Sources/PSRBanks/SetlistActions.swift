import SwiftUI
import PSRCore

@MainActor
enum SetlistActions {
    /// Asks before deleting a setlist; the patches it uses stay in the library.
    static func confirmDelete(_ s: SetlistMeta, store: LibraryStore, state: AppState) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete “\(s.name)”?"
        a.informativeText = "The setlist (\(store.filledCount(s)) of 32 slots filled) will be removed. Its patches stay in your library. This cannot be undone."
        a.addButton(withTitle: "Cancel")
        let b = a.addButton(withTitle: "Delete Setlist")
        b.hasDestructiveAction = true
        guard a.runModal() == .alertSecondButtonReturn else { return }
        if state.selection == .setlist(s.id) { state.selection = .patches }
        store.deleteSetlist(s.id)
    }
}
