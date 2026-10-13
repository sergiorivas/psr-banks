import SwiftUI
import PSRCore
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
        } detail: {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                switch state.selection {
                case .setlist(let id):
                    if store.setlist(id) != nil { SetlistEditorView(setlistID: id).id(id) } else { EmptyState() }
                case .patches:
                    PatchLibraryView()
                case nil:
                    EmptyState()
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { state.showImporter = true } label: { Label("Import USR", systemImage: "square.and.arrow.down") }
                    .help("Import a .USR backup from the keyboard (⌘O)")
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { c in Label(c.title, systemImage: c.icon).tag(c.rawValue) }
                    }.pickerStyle(.inline)
                } label: { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                    .help("Light / dark theme")
            }
        }
        .fileImporter(isPresented: $state.showImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { state.pendingImport = .init(plan: try store.makeImportPlan(from: url)) }
                catch { store.lastError = error.localizedDescription }
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
        .sheet(item: $state.pendingImport) { pending in
            ImportSheet(plan: pending.plan)
                .environmentObject(store)
                .environmentObject(state)
                .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
        }
        .sheet(isPresented: Binding(get: { state.infoPatchID != nil }, set: { if !$0 { state.infoPatchID = nil } })) {
            if let id = state.infoPatchID {
                PatchInfoSheet(patchID: id).environmentObject(store)
                    .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
            }
        }
        .sheet(isPresented: Binding(get: { state.infoSetlistID != nil }, set: { if !$0 { state.infoSetlistID = nil } })) {
            if let id = state.infoSetlistID {
                SetlistInfoSheet(setlistID: id).environmentObject(store)
                    .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
            }
        }
        .sheet(isPresented: Binding(get: { state.taggingPatchID != nil }, set: { if !$0 { state.taggingPatchID = nil } })) {
            if let id = state.taggingPatchID {
                PatchTagSheet(patchID: id).environmentObject(store)
                    .preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
            }
        }
        .sheet(isPresented: $state.showShortcuts) {
            ShortcutsSheet().preferredColorScheme(AppearanceChoice(rawValue: appearance)?.scheme)
        }
        .alert("Library notice", isPresented: Binding(get: { store.loadWarning != nil }, set: { if !$0 { store.loadWarning = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.loadWarning ?? "") }
        .alert("Something went wrong", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.lastError ?? "") }
    }
}

struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "pianokeys").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Pick something from the sidebar").foregroundStyle(.secondary)
        }
    }
}

struct Sidebar: View {
    /// Finder-style rename for a setlist row: the click that selects it must not also start editing.
    private func setlistRename(_ s: SetlistMeta) -> RenameConfig {
        RenameConfig(
            isEditing: state.renaming == .setlist(s.id),
            wasSelected: { state.selection == .setlist(s.id) && Date().timeIntervalSince(state.selectionChangedAt) > 0.8 },
            select: { state.selection = .setlist(s.id) },
            begin: { state.selection = .setlist(s.id); state.renaming = .setlist(s.id) },
            commit: { name in
                let t = name.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty, t != s.name { store.renameSetlist(s.id, to: t) }
                state.renaming = nil
            },
            cancel: { state.renaming = nil })
    }

    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text("PSR Banks").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("PSR-E483 registrations").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            List(selection: $state.selection) {
                Section("Library") {
                    Label("Patches", systemImage: "square.stack.3d.up")
                        .badge(store.patches.count)
                        .tag(AppState.Selection.patches)
                }
                Section {
                    ForEach(store.setlists.filter { $0.matches(search: "", tags: state.tagFilter) }) { s in
                        HStack {
                            Label {
                                RenameableName(text: s.name, font: .system(size: 13), config: setlistRename(s))
                            } icon: {
                                Image(systemName: store.isComplete(s) ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2")
                            }
                            Spacer()
                            if !store.isComplete(s) { Text("\(store.filledCount(s))/32").font(.caption2).foregroundStyle(.secondary) }
                        }
                        .tag(AppState.Selection.setlist(s.id))
                        .contextMenu {
                            Button("Rename") { state.selection = .setlist(s.id); state.renaming = .setlist(s.id) }
                            Button("Duplicate") { store.duplicateSetlist(s.id) }
                            Button("Show Info") { state.infoSetlistID = s.id }
                            Divider()
                            Button("Delete…", role: .destructive) { SetlistActions.confirmDelete(s, store: store, state: state) }
                        }
                    }
                    if !state.tagFilter.isEmpty && !store.setlists.contains(where: { $0.matches(search: "", tags: state.tagFilter) }) {
                        Text("No setlist has these tags").font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        let s = store.createSetlist(name: "New Setlist")
                        state.selection = .setlist(s.id)
                    } label: {
                        Label("New Setlist", systemImage: "plus.circle")
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Create an empty setlist (⌘N)")
                } header: {
                    Text("Setlists")
                }
            }
            .listStyle(.sidebar)
            .onKeyPress(.delete) {
                guard state.renaming == nil, case .setlist(let id) = state.selection, let s = store.setlist(id) else { return .ignored }
                SetlistActions.confirmDelete(s, store: store, state: state); return .handled
            }
            .onKeyPress(.return) {
                guard state.renaming == nil, case .setlist(let id) = state.selection else { return .ignored }
                state.renaming = .setlist(id); return .handled
            }
            SidebarTags()
            LibraryFooter()
        }
    }
}

/// Tags in use. Click to narrow the patch lists and the setlist list; click again to release.
struct SidebarTags: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState

    var body: some View {
        let tags = store.tagCounts
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                HStack {
                    Text("TAGS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if !state.tagFilter.isEmpty { Button("Clear") { state.tagFilter = [] }.buttonStyle(.link).font(.caption) }
                }
                ScrollView {
                    FlowLayout {
                        ForEach(tags) { t in
                            let on = state.tagFilter.contains { Tags.key($0) == t.id }
                            Button { state.toggleTag(t.name) } label: { TagBadge(tag: "\(t.name) \(t.total)", active: on) }
                                .buttonStyle(.plain)
                                .help("\(t.patches) patches, \(t.setlists) setlists")
                        }
                    }
                }.frame(maxHeight: 110)
            }
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
        }
    }
}

struct LibraryFooter: View {
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "folder").foregroundStyle(.secondary)
                Text(store.root.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(AppVersion.display).font(.caption2).foregroundStyle(.tertiary).help("PSR Banks \(AppVersion.display)")
                Menu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.root]) }
                    Button("Choose Library Folder…") { chooseFolder() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder to hold your patches and setlists"
        if panel.runModal() == .OK, let url = panel.url { store.useLibrary(at: url) }
    }
}
