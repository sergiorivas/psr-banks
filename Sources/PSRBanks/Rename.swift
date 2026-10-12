import SwiftUI
import PSRCore

/// What is currently being renamed in place (only one thing at a time, like Finder).
enum RenameTarget: Equatable {
    case patchRow(UUID)     // a row in the patch list
    case slot(Int)          // a slot of the open setlist
    case setlist(UUID)      // a setlist in the sidebar
}

/// How a name behaves when clicked and edited. Built by each screen so the editing view stays generic.
struct RenameConfig {
    var isEditing: Bool
    /// True when this item was already selected before the current click (so the click means "rename").
    var wasSelected: () -> Bool
    var select: () -> Void
    var begin: () -> Void
    var commit: (String) -> Void
    var cancel: () -> Void
}

/// A name that renames in place like a Finder file: click it once to select, click again to edit.
/// Double-click edits immediately. Return or clicking elsewhere commits, Esc cancels, the whole name starts selected.
struct RenameableName: View {
    let text: String
    var font: Font = .system(size: 13, weight: .semibold)
    let config: RenameConfig
    @State private var draft = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        if config.isEditing {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(font)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 1.5))
                .focused($focused)
                .onSubmit { finish(commit: true) }
                .onExitCommand { finish(commit: false) }
                .onChange(of: focused) { _, isFocused in if !isFocused { finish(commit: true) } }
                .onAppear {
                    draft = text
                    finished = false
                    focused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil) }
                }
        } else {
            Text(text)
                .font(font)
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { config.begin() }
                .onTapGesture { if config.wasSelected() { config.begin() } else { config.select() } }
        }
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit { config.commit(draft) } else { config.cancel() }
    }
}
