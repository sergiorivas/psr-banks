import SwiftUI
import PSRCore

@MainActor
final class AppState: ObservableObject {
    enum Selection: Hashable { case patches; case setlist(UUID) }
    struct PendingImport: Identifiable { let id = UUID(); let plan: ImportPlan }

    @Published var selection: Selection? = .patches { didSet { if selection != oldValue { selectionChangedAt = Date() } } }
    /// When the sidebar selection last changed; lets a click on an already-selected name mean "rename".
    var selectionChangedAt = Date.distantPast
    @Published var showImporter = false
    @Published var pendingImport: PendingImport?
    /// Tags every list is currently narrowed to (a patch/setlist must carry all of them).
    /// What the current drag carries (set when a drag starts; the drop also reads the pasteboard as a fallback).
    var dragging: DragItem?
    /// Patch whose info sheet is open (can be requested from any list).
    @Published var infoPatchID: UUID?
    @Published var tagFilter: Set<String> = []
    /// Slot highlighted in the open setlist, and row highlighted in the patch list: the targets of ⌘I / ⌘R / ⌘T.
    @Published var selectedSlot: Int? = 0
    @Published var selectedPatchID: UUID? { didSet { if selectedPatchID != oldValue { patchSelectionChangedAt = Date() } } }
    var patchSelectionChangedAt = Date.distantPast
    /// Bank (1-based) highlighted in the open setlist; exclusive with `selectedSlot`.
    @Published var selectedBank: Int?
    @Published var infoSetlistID: UUID?
    @Published var renaming: RenameTarget?
    @Published var taggingPatchID: UUID?
    @Published var showShortcuts = false
    @Published var searchFocusTick = 0

    /// The patch the patch-level shortcuts act on.
    func currentPatchID(in store: LibraryStore) -> UUID? {
        switch selection {
        case .setlist(let id):
            guard let s = store.setlist(id), let p = selectedSlot, s.slots.indices.contains(p), let pid = s.slots[p], store.patch(pid) != nil else { return nil }
            return pid
        case .patches: return selectedPatchID.flatMap { store.patch($0) != nil ? $0 : nil }
        case nil: return nil
        }
    }

    func toggleTag(_ t: String) {
        if let existing = tagFilter.first(where: { Tags.key($0) == Tags.key(t) }) { tagFilter.remove(existing) } else { tagFilter.insert(t) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PSRBanksApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LibraryStore()
    @StateObject private var state = AppState()
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue

    init() {
        // Developer aid: `PSRBanks --render-icons out.png` writes a contact sheet of every instrument icon and exits.
        if let i = CommandLine.arguments.firstIndex(of: "--render-icons"), CommandLine.arguments.count > i + 1 {
            MainActor.assumeIsolated { IconSheet.render(to: CommandLine.arguments[i + 1]) }
            exit(0)
        }
    }

    private var openSetlistID: UUID? { if case .setlist(let id) = state.selection { return store.setlist(id) != nil ? id : nil } else { return nil } }
    private var openSetlistIsComplete: Bool { openSetlistID.flatMap(store.setlist).map(store.isComplete) ?? false }

    var body: some Scene {
        WindowGroup("PSR Banks") {
            ContentView()
                .environmentObject(store)
                .environmentObject(state)
                .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
                .frame(minWidth: 1020, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Setlist") {
                    let s = store.createSetlist(name: "New Setlist")
                    state.selection = .setlist(s.id)
                }.keyboardShortcut("n")
                Button("Import USR File…") { state.showImporter = true }.keyboardShortcut("o")
                Divider()
                Button("Export Setlist as USR…") { if case .setlist(let id) = state.selection { ExportAction.run(id, store: store) } }
                    .keyboardShortcut("e")
                    .disabled(!openSetlistIsComplete)
                Button("Rename Setlist") { if let id = openSetlistID { state.renaming = .setlist(id) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(openSetlistID == nil)
                Button("Duplicate Setlist") { if case .setlist(let id) = state.selection { store.duplicateSetlist(id) } }
                    .keyboardShortcut("d")
                    .disabled(openSetlistID == nil)
            }
            CommandMenu("Go") {
                Button("Patches") { state.selection = .patches }.keyboardShortcut("1")
                ForEach(Array(store.setlists.prefix(8).enumerated()), id: \.element.id) { i, s in
                    Button(s.name) { state.selection = .setlist(s.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 2))), modifiers: .command)
                }
                Divider()
                Button("Search") { state.searchFocusTick += 1 }.keyboardShortcut("f")
            }
            CommandMenu("Patch") {
                Button("Show Info") { if let id = state.currentPatchID(in: store) { state.infoPatchID = id } }
                    .keyboardShortcut("i").disabled(state.currentPatchID(in: store) == nil)
                Button("Rename…") {
                    switch state.selection {
                    case .setlist: if let p = state.selectedSlot { state.renaming = .slot(p) }
                    case .patches: if let id = state.selectedPatchID { state.renaming = .patchRow(id) }
                    case nil: break
                    }
                }
                .keyboardShortcut("r").disabled(state.currentPatchID(in: store) == nil)
                Button("Edit Tags…") { if let id = state.currentPatchID(in: store) { state.taggingPatchID = id } }
                    .keyboardShortcut("t").disabled(state.currentPatchID(in: store) == nil)
                Divider()
                Button(state.currentPatchID(in: store).map { $0 == store.blankPatchID } == true ? "Use Built-in Blank Patch" : "Set as Blank Patch") {
                    if let id = state.currentPatchID(in: store) { store.setBlankPatch(id == store.blankPatchID ? nil : id) }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(state.currentPatchID(in: store) == nil)
                Button("Use Blank Patch in Slot") {
                    if case .setlist(let id) = state.selection, let p = state.selectedSlot { store.useBlankPatch(in: id, at: p) }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift]).disabled(openSetlistID == nil)
                Button("Fill Empty Slots with Blank Patch") { if let id = openSetlistID { store.fillEmptySlots(of: id) } }
                    .keyboardShortcut("f", modifiers: [.command, .shift]).disabled(openSetlistID == nil)
                Divider()
                Button("Clear Slot") {
                    if case .setlist(let id) = state.selection, let p = state.selectedSlot { store.setSlot(p, of: id, to: nil) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(state.currentPatchID(in: store) == nil || openSetlistID == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { state.showShortcuts = true }.keyboardShortcut("/")
            }
        }
    }
}
