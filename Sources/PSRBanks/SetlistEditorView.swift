import SwiftUI
import PSRCore
import UniformTypeIdentifiers

struct SetlistEditorView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let setlistID: UUID
    @State private var nameDraft = ""
    @State private var search = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var searchFocused: Bool

    private var setlist: SetlistMeta? { store.setlist(setlistID) }

    var body: some View {
        if let s = setlist {
            VStack(alignment: .leading, spacing: 16) {
                header(s)
                HStack(alignment: .top, spacing: 16) {
                    Card { SlotGrid(setlist: s, selected: $state.selectedSlot, editTags: { state.taggingPatchID = $0.id }) }
                        .frame(maxWidth: .infinity, alignment: .top)
                    patchPicker.frame(width: 320)
                }
            }
            .padding(22)
            .onAppear { nameDraft = s.name }
            .onChange(of: state.searchFocusTick) { _, _ in searchFocused = true }
        }
    }

    // MARK: Header

    private func header(_ s: SetlistMeta) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Setlist name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onExitCommand { nameDraft = setlist?.name ?? ""; nameFocused = false }
                    .onChange(of: nameFocused) { _, f in if !f { commitName() } }
                HStack(spacing: 8) {
                    ProgressView(value: Double(store.filledCount(s)), total: 32).frame(width: 120)
                    Text("\(store.filledCount(s)) of 32 slots filled" + (store.missingCount(s) > 0 ? " · \(store.missingCount(s)) patch\(store.missingCount(s) == 1 ? "" : "es") missing from the library" : "")).font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(s.tags, id: \.self) { t in TagBadge(tag: t) }
                    TagButton(title: "Tags for this setlist", tags: s.tags) { store.setTags($0, forSetlist: s.id) }
                }
            }
            Spacer()
            Menu {
                Button("Duplicate") { store.duplicateSetlist(s.id) }
                Button("Show Info") { state.infoSetlistID = s.id }
                Divider()
                Button("Delete…", role: .destructive) { SetlistActions.confirmDelete(s, store: store, state: state) }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            Button { export(s) } label: { Label("Export USR…", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isComplete(s))
                .help(store.isComplete(s) ? "Write a .USR file you can copy to the keyboard" : "Fill all 32 slots to export")
        }
    }

    private func commitName() {
        let t = nameDraft.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { nameDraft = setlist?.name ?? "" } else if t != setlist?.name { store.renameSetlist(setlistID, to: t) }
    }

    // MARK: Patch picker

    private var pickerPatches: [Patch] { store.patches.filter { $0.matches(search: search, tags: state.tagFilter) } }

    private var patchPicker: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Patch library").font(.headline)
                Text(state.selectedSlot.map { "Drag a patch onto a slot, or double-click it to put it in \(SlotLayout.label(at: $0))." } ?? "Drag a patch onto a slot.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search name, voice or tag", text: $search).textFieldStyle(.plain).focused($searchFocused)
                }
                .padding(8).background(Theme.well, in: RoundedRectangle(cornerRadius: 8))
                TagFilterBar()
                List {
                    ForEach(pickerPatches) { p in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 3) {
                                PatchTitle(patch: p, nameSize: 13)
                                TagRow(tags: p.meta.tags, limit: 3, compact: true)
                            }
                            Spacer(minLength: 4)
                            if p.meta.splitOn { Chip(text: "S", color: Theme.warn) }
                            if p.meta.dualOn { Chip(text: "D", color: Theme.good) }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { if let sel = state.selectedSlot { place(p.id, at: sel) } }
                        .onDrag {
                            state.dragging = .patch(p.id)
                            return NSItemProvider(object: DragItem.patch(p.id).payload as NSString)
                        }
                        .contextMenu {
                            Button("Show Info") { state.infoPatchID = p.id }
                            IconMenu(patch: p)
                        }
                        .help(p.meta.tags.isEmpty ? p.name : p.name + "  " + p.meta.tags.map { "#\($0)" }.joined(separator: " "))
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(minHeight: 360)
            }
        }
    }

    // MARK: Actions

    private func place(_ patchID: UUID, at position: Int) {
        store.setSlot(position, of: setlistID, to: patchID)
        state.selectedSlot = min(position + 1, 31)
    }

    private func export(_ s: SetlistMeta) { ExportAction.run(s.id, store: store) }
}

/// 8 banks (rows) × 4 memories (columns). Position in the file is memory-major, handled via `SlotLayout`.
struct SlotGrid: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let setlist: SetlistMeta
    @Binding var selected: Int?
    let editTags: (Patch) -> Void
    @State private var targeted: Int?
    @State private var keyMonitor: Any?
    private let bankLabelWidth: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Color.clear.frame(width: bankLabelWidth, height: 1)
                ForEach(1...SlotLayout.memories, id: \.self) { m in
                    Text("Memory \(m)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(1...SlotLayout.banks, id: \.self) { bank in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.bankHues[bank - 1]).frame(width: 8, height: 8)
                            Text("Bank \(bank)").font(.system(size: 12, weight: .semibold, design: .rounded))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { grabKeyboard(); state.selectedBank = bank; selected = nil }
                        .contextMenu {
                            Button("Delete Bank…", role: .destructive) { confirmDeleteBank(bank) }
                        }
                        BankDescriptionField(setlistID: setlist.id, bank: bank, text: setlist.bankDescriptions[bank - 1])
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(state.selectedBank == bank ? Theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(state.selectedBank == bank ? Theme.accent : .clear, lineWidth: 2))
                    .frame(width: bankLabelWidth, alignment: .leading)
                    ForEach(1...SlotLayout.memories, id: \.self) { memory in
                        let pos = SlotLayout.position(bank: bank, memory: memory)
                        let patch = store.patch(setlist.slots[pos])
                        SlotCell(position: pos, patch: patch, rename: patch.map { renameConfig(pos, $0) }, missing: patch == nil && setlist.slots[pos] != nil, selected: selected == pos, dropTarget: targeted == pos, tint: Theme.bankHues[bank - 1])
                            .onTapGesture { grabKeyboard(); state.selectedBank = nil; selected = pos }
                            .onDrag {
                                state.dragging = .slot(pos)
                                return NSItemProvider(object: DragItem.slot(pos).payload as NSString)
                            }
                            .onDrop(of: [.plainText], delegate: SlotDropDelegate(position: pos, setlistID: setlist.id, store: store, state: state,
                                                                                 targeted: $targeted, selected: $selected))
                            .contextMenu {
                                Button("Paste Patch") { if let id = PatchClipboard.pasted(), store.patch(id) != nil { store.setSlot(pos, of: setlist.id, to: id) } }
                                    .disabled(PatchClipboard.pasted().flatMap { store.patch($0) } == nil)
                                Button("Use Blank Patch") { store.useBlankPatch(in: setlist.id, at: pos) }
                                if let p = patch {
                                    Divider()
                                    Button("Copy Patch") { PatchClipboard.copy(p.id) }
                                    Button("Set as Blank Patch") { store.setBlankPatch(p.id) }
                                    Divider()
                                    Button("Show Info") { state.infoPatchID = p.id }
                                    Button("Rename Patch") { selected = pos; state.renaming = .slot(pos) }
                                    IconMenu(patch: p)
                                    Menu("Tags") {
                                        ForEach(store.tagCounts) { t in
                                            Toggle(t.name, isOn: Binding(
                                                get: { Tags.contains(p.meta.tags, t.name) },
                                                set: { on in
                                                    store.setTags(on ? p.meta.tags + [t.name] : p.meta.tags.filter { Tags.key($0) != t.id }, forPatch: p.id)
                                                }))
                                        }
                                        if !store.tagCounts.isEmpty { Divider() }
                                        Button("New / Edit Tags…") { editTags(p) }
                                    }
                                    Button("Clear Slot") { store.setSlot(pos, of: setlist.id, to: nil) }
                                }
                            }
                    }
                }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handle(event) ? nil : event }
        }
        .onChange(of: selected) { _, new in if new != nil { state.selectedBank = nil } }
        .onDisappear { if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil } }
    }

    /// Delete on a slot: the slot gets the blank patch.
    private func deleteSlot(_ pos: Int) { store.useBlankPatch(in: setlist.id, at: pos) }

    /// Deleting a bank puts the blank patch in all 4 memories; asks first.
    private func confirmDeleteBank(_ bank: Int) {
        guard let d = store.ensureBlankPatch() else { return }
        let names = (1...SlotLayout.memories).compactMap { store.patch(setlist.slots[SlotLayout.position(bank: bank, memory: $0)])?.name }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete Bank \(bank)?"
        a.informativeText = "The 4 memories of Bank \(bank) in “\(setlist.name)” will be replaced by the blank patch “\(d.name)”."
            + (names.isEmpty ? "" : "\n\nCurrently:\n" + names.joined(separator: "\n")) + "\n\nThe patches stay in your library."
        a.addButton(withTitle: "Cancel")
        let b = a.addButton(withTitle: "Delete Bank")
        b.hasDestructiveAction = true
        if a.runModal() == .alertSecondButtonReturn { store.resetBankToBlank(bank, in: setlist.id) }
    }

    /// Takes keyboard focus away from the sidebar / lists so the arrow keys drive the grid.
    private func grabKeyboard() { NSApp.keyWindow?.makeFirstResponder(nil) }

    /// Finder-style rename of the patch in a slot: first click selects, a second click edits in place.
    private func renameConfig(_ pos: Int, _ p: Patch) -> RenameConfig {
        RenameConfig(
            isEditing: state.renaming == .slot(pos),
            wasSelected: { selected == pos },
            select: { grabKeyboard(); selected = pos },
            begin: { selected = pos; state.renaming = .slot(pos) },
            commit: { name in
                let t = name.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, t != p.name { store.renamePatch(p.id, to: t) }
                state.renaming = nil
                grabKeyboard()
            },
            cancel: { state.renaming = nil; grabKeyboard() })
    }

    /// Arrow keys move the selection (↑↓ banks, ←→ memories); ⌫ clears; Return renames; Space shows info.
    /// Handled at window level so it works whichever view had focus last; text fields, lists and sheets keep their own keys.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window = NSApp.keyWindow, window.sheetParent == nil, window.attachedSheet == nil, NSApp.modalWindow == nil,
              state.renaming == nil, case .setlist(let id) = state.selection, id == setlist.id else { return false }
        let responder = window.firstResponder
        if responder is NSTextView || responder is NSTableView || responder is NSOutlineView { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let bank = state.selectedBank, mods.isEmpty {
            switch event.keyCode {
            case 126: state.selectedBank = max(bank - 1, 1); return true                   // up
            case 125: state.selectedBank = min(bank + 1, SlotLayout.banks); return true    // down
            case 124:                                                                      // right: into the bank's first memory
                state.selectedBank = nil; selected = SlotLayout.position(bank: bank, memory: 1); return true
            case 51, 117: confirmDeleteBank(bank); return true
            default: return false
            }
        }
        guard let pos = selected, let current = store.setlist(id) else { return false }
        if mods == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "c":
                guard let pid = current.slots[pos], store.patch(pid) != nil else { return false }
                PatchClipboard.copy(pid); return true
            case "x":
                guard let pid = current.slots[pos], store.patch(pid) != nil else { return false }
                PatchClipboard.copy(pid); store.setSlot(pos, of: id, to: nil); return true
            case "v":
                guard let pid = PatchClipboard.pasted(), store.patch(pid) != nil else { return false }
                store.setSlot(pos, of: id, to: pid); return true
            default: return false
            }
        }
        guard mods.isEmpty else { return false }
        let bank = SlotLayout.bank(at: pos), memory = SlotLayout.memory(at: pos)
        func go(_ b: Int, _ m: Int) -> Bool {
            selected = SlotLayout.position(bank: min(max(b, 1), SlotLayout.banks), memory: min(max(m, 1), SlotLayout.memories))
            return true
        }
        let patch = store.patch(current.slots[pos])
        switch event.keyCode {
        case 126: return go(bank - 1, memory)          // up
        case 125: return go(bank + 1, memory)          // down
        case 123: return go(bank, memory - 1)          // left
        case 124: return go(bank, memory + 1)          // right
        case 51, 117:                                  // delete, forward delete: put the blank patch in the slot
            deleteSlot(pos)
            return true
        case 36, 76:                                   // return, enter
            guard patch != nil else { return false }
            state.renaming = .slot(pos); return true
        case 49:                                       // space
            guard let p = patch else { return false }
            state.infoPatchID = p.id; return true
        default: return false
        }
    }
}

/// Short editable phrase describing a bank ("Salsa", "Song SBC"). Saved on Return or when focus leaves.
struct BankDescriptionField: View {
    @EnvironmentObject var store: LibraryStore
    let setlistID: UUID
    let bank: Int
    let text: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Add description", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(1)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { _, t in if !focused { draft = t } }
            .onSubmit { commit() }
            .onExitCommand { draft = text; focused = false }
            .onChange(of: focused) { _, f in if !f { commit() } }
            .help("Describe what Bank \(bank) is for")
    }

    private func commit() {
        store.setBankDescription(draft, bank: bank, in: setlistID)
        draft = draft.trimmingCharacters(in: .whitespaces)
    }
}

struct SlotDropDelegate: DropDelegate {
    let position: Int
    let setlistID: UUID
    let store: LibraryStore
    let state: AppState
    @Binding var targeted: Int?
    @Binding var selected: Int?

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { targeted = position }
    func dropExited(info: DropInfo) { if targeted == position { targeted = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: state.dragging.map { if case .slot = $0 { return .move } else { return .copy } } ?? .copy) }

    func performDrop(info: DropInfo) -> Bool {
        targeted = nil
        if let item = state.dragging {
            state.dragging = nil
            return finish(item)
        }
        // Fallback: read the dragged text itself.
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let item = DragItem(payload: s) else { return }
            DispatchQueue.main.async { _ = finish(item) }
        }
        return true
    }

    private func finish(_ item: DragItem) -> Bool {
        let ok = store.apply(item, to: position, in: setlistID)
        if ok { selected = position }
        return ok
    }
}

struct SlotCell: View {
    let position: Int
    let patch: Patch?
    var rename: RenameConfig?
    var missing = false
    let selected: Bool
    let dropTarget: Bool
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 8) {
            if let p = patch { InstrumentBadge(icon: p.icon, size: 28) }
            VStack(alignment: .leading, spacing: 3) {
                if let p = patch {
                    if let rename { RenameableName(text: p.name, font: .system(size: 12, weight: .semibold), config: rename) }
                    else { Text(p.name).font(.system(size: 12, weight: .semibold)).lineLimit(1) }
                    HStack(spacing: 4) {
                        Text("\(p.meta.mainVoice) · \(VoiceCatalog.name(for: p.meta.mainVoice))").lineLimit(1)
                        Spacer(minLength: 0)
                        if p.meta.splitOn { Chip(text: "S", color: Theme.warn) }
                        if p.meta.dualOn { Chip(text: "D", color: Theme.good) }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    TagRow(tags: p.meta.tags, limit: 3, compact: true)
                } else {
                    Text(missing ? "Missing patch" : "Empty").font(.system(size: 12)).foregroundStyle(missing ? AnyShapeStyle(Theme.warn) : AnyShapeStyle(.tertiary))
                    Text(missing ? "its file was deleted — drop another" : "drop a patch here").font(.system(size: 10)).foregroundStyle(.quaternary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(dropTarget ? Theme.accent.opacity(0.22) : (patch == nil ? Theme.well : tint.opacity(0.14)), in: shape)
        .overlay(shape.stroke(dropTarget || selected ? Theme.accent : (patch == nil ? Theme.stroke : tint.opacity(0.35)),
                              style: StrokeStyle(lineWidth: dropTarget || selected ? 2 : 1, dash: patch == nil && !selected && !dropTarget ? [4, 3] : [])))
        .contentShape(shape)
        .help(patch.map { "\(SlotLayout.label(at: position)) — \($0.name)" + ($0.meta.tags.isEmpty ? "" : "  " + $0.meta.tags.map { "#\($0)" }.joined(separator: " ")) }
              ?? SlotLayout.label(at: position))
    }
}
