import SwiftUI
import PSRCore

struct PatchLibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?
    @State private var multiSelection: Set<UUID> = []

    private var filtered: [Patch] { store.patches.filter { $0.matches(search: search, tags: state.tagFilter) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                LogoMark(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Patches").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(subtitle).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.showImporter = true } label: { Label("Import USR…", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.borderedProminent)
            }
            if store.patches.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("No patches yet").font(.headline)
                        Text("Import a .USR backup to pull its memory slots into your library.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 220)
                }
            } else {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search name, voice or tag", text: $search).textFieldStyle(.plain)
                                .focused($searchFocused)
                        }
                        TagFilterBar()
                        Divider()
                        if filtered.isEmpty {
                            Text("No patch matches this search.").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            List(selection: listSelection) {
                                ForEach(filtered) { p in
                                    PatchRow(patch: p, select: { multiSelection = [p.id]; state.selectedPatchID = p.id }).tag(p.id)
                                }
                            }
                            .listStyle(.plain).scrollContentBackground(.hidden)
                            .onChange(of: state.selectedPatchID) { _, id in
                                if let id, !multiSelection.contains(id) { multiSelection = [id] }
                            }
                            .onAppear { if let id = state.selectedPatchID { multiSelection = [id] } }
                            .onDeleteCommand { confirmDelete(multiSelection) }
                            .onKeyPress(.return) {
                                guard state.renaming == nil, let id = state.selectedPatchID, filtered.contains(where: { $0.id == id }) else { return .ignored }
                                state.renaming = .patchRow(id); return .handled
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
        .onChange(of: state.searchFocusTick) { _, _ in searchFocused = true }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // ⌘C on the selected row copies the patch; everything else (text fields, sheets) is left alone.
                guard let window = NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil, state.renaming == nil,
                      case .patches = state.selection, !(window.firstResponder is NSTextView), let id = state.selectedPatchID, store.patch(id) != nil,
                      event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "c" else { return event }
                PatchClipboard.copy(id); return nil
            }
        }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }
    }

    /// Writes the multi-selection and the single selected patch together so a click never leaves them out of step.
    private var listSelection: Binding<Set<UUID>> {
        Binding(get: { multiSelection }, set: { new in
            multiSelection = new
            state.selectedPatchID = new.count == 1 ? new.first : nil
        })
    }

    /// Asks before deleting the selected patches; patches still used by a setlist are kept.
    private func confirmDelete(_ ids: Set<UUID>) {
        guard state.renaming == nil else { return }
        let patches = store.patches.filter { ids.contains($0.id) }
        guard !patches.isEmpty else { return }
        let deletable = patches.filter { store.usageCount(of: $0.id) == 0 }
        let kept = patches.count - deletable.count
        let a = NSAlert()
        a.alertStyle = .warning
        if deletable.isEmpty {
            a.messageText = patches.count == 1 ? "“\(patches[0].name)” is in use" : "These patches are in use"
            a.informativeText = "Remove them from every setlist before deleting."
            a.addButton(withTitle: "OK")
            a.runModal(); return
        }
        a.messageText = deletable.count == 1 ? "Delete “\(deletable[0].name)”?" : "Delete \(deletable.count) patches?"
        a.informativeText = (kept > 0 ? "\(kept) selected patch\(kept == 1 ? " is" : "es are") used in a setlist and will be kept. " : "") + "This cannot be undone."
        a.addButton(withTitle: "Cancel")
        let b = a.addButton(withTitle: deletable.count == 1 ? "Delete Patch" : "Delete Patches")
        b.hasDestructiveAction = true
        guard a.runModal() == .alertSecondButtonReturn else { return }
        for p in deletable { store.deletePatch(p.id) }
        multiSelection = multiSelection.subtracting(deletable.map(\.id))
    }

    private var subtitle: String {
        filtered.count == store.patches.count ? "\(store.patches.count) saved memory slots" : "\(filtered.count) of \(store.patches.count) shown"
    }
}

/// Tag chips that narrow every list; also lives in the sidebar.
struct TagFilterBar: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState

    var body: some View {
        let tags = store.tagCounts
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Image(systemName: "tag").foregroundStyle(.secondary).font(.caption)
                    ForEach(tags) { t in
                        let on = state.tagFilter.contains { Tags.key($0) == t.id }
                        Button { state.toggleTag(t.name) } label: { TagBadge(tag: t.name, active: on) }.buttonStyle(.plain)
                    }
                    if !state.tagFilter.isEmpty {
                        Button("Clear") { state.tagFilter = [] }.buttonStyle(.link).font(.caption)
                    }
                }
            }
        }
    }
}

struct PatchRow: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let patch: Patch
    let select: () -> Void
    @State private var hovering = false

    private var renameConfig: RenameConfig {
        RenameConfig(
            isEditing: state.renaming == .patchRow(patch.id),
            wasSelected: { state.selectedPatchID == patch.id && Date().timeIntervalSince(state.patchSelectionChangedAt) > 0.8 },
            select: select,
            begin: { select(); state.renaming = .patchRow(patch.id) },
            commit: { name in
                let t = name.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, t != patch.name { store.renamePatch(patch.id, to: t) }
                state.renaming = nil
            },
            cancel: { state.renaming = nil })
    }

    var body: some View {
        HStack(spacing: 12) {
            PatchTitle(patch: patch, nameSize: 14, iconEditable: true, rename: renameConfig)
            Spacer(minLength: 8)
            TagRow(tags: patch.meta.tags, limit: 3)
            if store.blankPatchID == patch.id { Chip(text: "★ BLANK", color: Theme.accent) }
            if patch.meta.splitOn { Chip(text: "SPLIT", color: Theme.warn) }
            if patch.meta.dualOn { Chip(text: "DUAL", color: Theme.good) }
            let used = store.usageCount(of: patch.id)
            Text(used == 0 ? "unused" : "in \(used) slot\(used == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
            HStack(spacing: 2) {
                Button { state.infoPatchID = patch.id } label: { Image(systemName: "info.circle") }.help("Show all properties")
                TagButton(title: "Tags for “\(patch.name)”", tags: patch.meta.tags) { store.setTags($0, forPatch: patch.id) }
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // A plain click anywhere on the row selects it (the drag handler otherwise swallows clicks on the empty space);
        // clicks with ⌘/⇧ are left to the list so multi-select keeps working.
        .onTapGesture {
            if NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty { select() }
        }
        .onDrag {
            state.dragging = .patch(patch.id)
            return NSItemProvider(object: DragItem.patch(patch.id).payload as NSString)
        }
        .contextMenu {
            Button("Show Info") { state.infoPatchID = patch.id }
            Button("Copy Patch") { PatchClipboard.copy(patch.id) }
            Button(store.blankPatchID == patch.id ? "Use Built-in Blank Patch" : "Set as Blank Patch") {
                store.setBlankPatch(store.blankPatchID == patch.id ? nil : patch.id)
            }
            Button("Rename") { select(); state.renaming = .patchRow(patch.id) }
            IconMenu(patch: patch)
            Button("Delete", role: .destructive) { store.deletePatch(patch.id) }
        }
    }
}
