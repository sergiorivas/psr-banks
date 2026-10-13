import Foundation
import SwiftUI

public enum LibraryError: LocalizedError {
    case incomplete(Int)
    case patchInUse(String)
    case missingPatch

    public var errorDescription: String? {
        switch self {
        case .incomplete(let n): return "The setlist has \(n) empty slot\(n == 1 ? "" : "s"). Fill all 32 before exporting."
        case .patchInUse(let n): return "“\(n)” is used by a setlist. Remove it from the setlists first."
        case .missingPatch: return "A patch referenced by this setlist is missing from the library."
        }
    }
}

/// The library is a folder:
/// ```
/// Library/
///   Patches/<uuid>.patch/{record.bin, meta.json}
///   Setlists/<uuid>.setlist/setlist.json
/// ```
@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var patches: [Patch] = []
    @Published public private(set) var setlists: [SetlistMeta] = []
    @Published public private(set) var root: URL
    @Published public var lastError: String?
    /// The blank patch: what deleting a slot or a bank puts back. Stored as `defaultPatchID` in library.json (older name).
    @Published public private(set) var blankPatchID: UUID?
    private var info = LibraryInfo()
    private let seedsBlank: Bool
    /// Set when `reload` had to skip or repair something; shown once to the user.
    @Published public var loadWarning: String?

    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static let defaultsKey = "libraryPath"

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("PSR Banks Library")
    }

    /// The library's own blank patch is created from the built-in one (see `ensureBlankPatch`) when the app opens its real library.
    public init(root: URL? = nil, seedBlankPatch: Bool? = nil) {
        seedsBlank = seedBlankPatch ?? (root == nil)
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey).map { URL(fileURLWithPath: $0) }
        self.root = root ?? saved ?? Self.defaultRoot
        reload()
    }

    private var patchesDir: URL { root.appendingPathComponent("Patches") }
    private var setlistsDir: URL { root.appendingPathComponent("Setlists") }

    public func useLibrary(at url: URL) {
        root = url
        UserDefaults.standard.set(url.path, forKey: Self.defaultsKey)
        reload()
    }

    public func reload() {
        try? fm.createDirectory(at: patchesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: setlistsDir, withIntermediateDirectories: true)
        var loadedPatches: [Patch] = []
        var skipped = 0, repaired = 0
        for dir in (try? fm.contentsOfDirectory(at: patchesDir, includingPropertiesForKeys: nil)) ?? [] where dir.pathExtension == "patch" {
            guard let m = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
                  let meta = try? decoder.decode(PatchMeta.self, from: m),
                  let bin = try? Data(contentsOf: dir.appendingPathComponent("record.bin")),
                  bin.count == USRFile.patchSize else { skipped += 1; continue }
            loadedPatches.append(Patch(meta: meta, data: bin))
        }
        patches = loadedPatches.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var loadedSetlists: [SetlistMeta] = []
        for dir in (try? fm.contentsOfDirectory(at: setlistsDir, includingPropertiesForKeys: nil)) ?? [] where dir.pathExtension == "setlist" {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent("setlist.json")),
                  var s = try? decoder.decode(SetlistMeta.self, from: d) else { skipped += 1; continue }
            // A hand-edited or damaged file must never be able to crash the UI: force 32 slots and a valid header.
            if s.slots.count != USRFile.patchCount {
                s.slots = Array((s.slots + Array(repeating: nil, count: USRFile.patchCount)).prefix(USRFile.patchCount)); repaired += 1
            }
            if s.header.count != USRFile.headerSize { s.header = USRFile.defaultHeader; repaired += 1 }
            loadedSetlists.append(s)
        }
        loadWarning = (skipped == 0 && repaired == 0) ? nil :
            [skipped > 0 ? "\(skipped) unreadable item\(skipped == 1 ? " was" : "s were") skipped" : nil,
             repaired > 0 ? "\(repaired) setlist\(repaired == 1 ? " was" : "s were") repaired" : nil]
            .compactMap { $0 }.joined(separator: " and ") + " while loading the library at \(root.path)."

        setlists = loadedSetlists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        loadInfo()
    }

    // MARK: Library info (version + blank patch)

    private var infoURL: URL { root.appendingPathComponent("library.json") }

    private func loadInfo() {
        if let d = try? Data(contentsOf: infoURL), let i = try? decoder.decode(LibraryInfo.self, from: d) { info = i } else { info = LibraryInfo() }
        if let id = info.defaultPatchID, patch(id) == nil { info.defaultPatchID = nil }   // its folder was deleted
        blankPatchID = info.defaultPatchID
        adoptBlankByName()
        if seedsBlank { ensureBlankPatch() }
        // Only stamp libraries that are not from a newer app.
        if info.formatVersion <= AppVersion.libraryFormat, info.appVersion != AppVersion.marketing {
            info.appVersion = AppVersion.marketing
        }
        saveInfo()
    }

    private func saveInfo() {
        do { try encoder.encode(info).write(to: infoURL, options: .atomic) } catch { lastError = "Could not save library info: \(error.localizedDescription)" }
    }

    public var blankPatch: Patch? { patch(blankPatchID) }

    /// A patch with this name is the blank patch whenever none has been marked explicitly.
    public static let blankPatchName = "Default <BLANK>"

    private func adoptBlankByName() {
        guard blankPatchID == nil, let blank = patches.first(where: { $0.name == Self.blankPatchName }) else { return }
        markBlank(blank.id)
    }

    private func markBlank(_ id: UUID?) {
        info.defaultPatchID = id
        blankPatchID = id
        saveInfo()
    }

    /// The blank patch, creating it from the copy shipped inside the app when the library has none.
    @discardableResult
    public func ensureBlankPatch() -> Patch? {
        if let p = blankPatch { return p }
        adoptBlankByName()
        if let p = blankPatch { return p }
        guard let url = Resources.url("blank_patch", "bin"), let data = try? Data(contentsOf: url), data.count == USRFile.patchSize else { return nil }
        let p = addPatch(record: data, name: Self.blankPatchName, source: "Built-in")
        markBlank(p.id)
        return p
    }

    // MARK: Locations on disk

    public func patchFolderURL(_ id: UUID) -> URL { patchesDir.appendingPathComponent("\(id.uuidString).patch") }
    public func setlistFolderURL(_ id: UUID) -> URL { setlistsDir.appendingPathComponent("\(id.uuidString).setlist") }

    /// Marks a patch as the blank patch (nil goes back to the built-in one).
    public func setBlankPatch(_ id: UUID?) {
        guard id == nil || patch(id) != nil else { return }
        markBlank(id)
    }

    /// Puts the blank patch into one slot.
    @discardableResult
    public func useBlankPatch(in setlistID: UUID, at position: Int) -> Bool {
        guard let d = ensureBlankPatch() else { return false }
        setSlot(position, of: setlistID, to: d.id)
        return true
    }

    /// Fills every empty (or missing-patch) slot with the blank patch; returns how many were filled.
    @discardableResult
    public func fillEmptySlots(of setlistID: UUID) -> Int {
        guard let d = ensureBlankPatch(), var s = setlist(setlistID) else { return 0 }
        var n = 0
        for i in s.slots.indices where patch(s.slots[i]) == nil { s.slots[i] = d.id; n += 1 }
        if n > 0 { updateSetlist(s) }
        return n
    }

    // MARK: Lookup

    public func patch(_ id: UUID?) -> Patch? { id.flatMap { id in patches.first { $0.id == id } } }
    public var knownHashes: [String: UUID] { Dictionary(patches.map { ($0.meta.hash, $0.id) }, uniquingKeysWith: { a, _ in a }) }
    public func setlist(_ id: UUID) -> SetlistMeta? { setlists.first { $0.id == id } }
    /// Slots that point at a patch that still exists. A setlist whose patch folders were deleted counts those as empty.
    public func filledCount(_ s: SetlistMeta) -> Int { s.slots.filter { patch($0) != nil }.count }
    public func isComplete(_ s: SetlistMeta) -> Bool { filledCount(s) == USRFile.patchCount }
    public func missingCount(_ s: SetlistMeta) -> Int { s.slots.compactMap { $0 }.filter { patch($0) == nil }.count }
    public func usageCount(of patchID: UUID) -> Int { setlists.reduce(0) { $0 + $1.slots.filter { $0 == patchID }.count } }

    // MARK: Patches

    private func uniqueName(_ base: String, excluding: UUID? = nil) -> String {
        let taken = Set(patches.filter { $0.id != excluding }.map { $0.name })
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    @discardableResult
    public func addPatch(record: Data, name: String?, source: String?, icon: InstrumentIcon? = nil) -> Patch {
        let hash = PatchInfo.hash(of: record)
        if let existing = patches.first(where: { $0.meta.hash == hash }) { return existing }
        let info = PatchInfo(record: record)
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        let meta = PatchMeta(id: UUID(), name: uniqueName(trimmed?.isEmpty == false ? trimmed! : info.suggestedName),
                             hash: hash, mainVoice: info.mainVoice, splitOn: info.splitOn, dualOn: info.dualOn,
                             createdAt: Date(), source: source, icon: icon)
        let patch = Patch(meta: meta, data: record)
        write(patch)
        patches.append(patch)
        sortPatches()
        adoptBlankByName()
        return patch
    }

    public func renamePatch(_ id: UUID, to name: String) {
        guard let i = patches.firstIndex(where: { $0.id == id }) else { return }
        patches[i].meta.name = name
        write(patches[i])
        adoptBlankByName()
    }

    /// Pass nil to go back to the automatic icon.
    public func setIcon(_ icon: InstrumentIcon?, forPatch id: UUID) {
        guard let i = patches.firstIndex(where: { $0.id == id }) else { return }
        patches[i].meta.icon = icon
        write(patches[i])
    }

    public func deletePatch(_ id: UUID) {
        guard let p = patch(id) else { return }
        guard usageCount(of: id) == 0 else { lastError = LibraryError.patchInUse(p.name).localizedDescription; return }
        try? fm.removeItem(at: patchesDir.appendingPathComponent("\(id.uuidString).patch"))
        patches.removeAll { $0.id == id }
        if blankPatchID == id { markBlank(nil) }
    }

    private func sortPatches() { patches.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    private func write(_ p: Patch) {
        let dir = patchesDir.appendingPathComponent("\(p.id.uuidString).patch")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try p.data.write(to: dir.appendingPathComponent("record.bin"), options: .atomic)
            try encoder.encode(p.meta).write(to: dir.appendingPathComponent("meta.json"), options: .atomic)
        } catch { lastError = "Could not save patch: \(error.localizedDescription)" }
    }

    // MARK: Tags

    public func setTags(_ tags: [String], forPatch id: UUID) {
        guard let i = patches.firstIndex(where: { $0.id == id }) else { return }
        patches[i].meta.tags = Tags.normalized(tags)
        write(patches[i])
    }

    public func setTags(_ tags: [String], forSetlist id: UUID) {
        guard var s = setlist(id) else { return }
        s.tags = Tags.normalized(tags)
        updateSetlist(s)
    }

    /// Every tag in use, with how many patches / setlists carry it, most used first.
    public var tagCounts: [TagCount] {
        var spelling: [String: String] = [:]
        var p: [String: Int] = [:], s: [String: Int] = [:]
        for t in patches.flatMap({ $0.meta.tags }) { spelling[Tags.key(t), default: t] = spelling[Tags.key(t)] ?? t; p[Tags.key(t), default: 0] += 1 }
        for t in setlists.flatMap({ $0.tags }) { spelling[Tags.key(t), default: t] = spelling[Tags.key(t)] ?? t; s[Tags.key(t), default: 0] += 1 }
        return spelling.map { TagCount(name: $0.value, patches: p[$0.key] ?? 0, setlists: s[$0.key] ?? 0) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Setlists

    @discardableResult
    public func createSetlist(name: String, slots: [UUID?]? = nil, header: Data? = nil, tags: [String] = [], bankDescriptions: [String]? = nil) -> SetlistMeta {
        var s = SetlistMeta(id: UUID(), name: name, createdAt: Date(),
                            slots: slots ?? Array(repeating: nil, count: USRFile.patchCount),
                            header: header ?? USRFile.defaultHeader, tags: tags)
        if let bankDescriptions { s.bankDescriptions = Array((bankDescriptions + Array(repeating: "", count: SlotLayout.banks)).prefix(SlotLayout.banks)) }
        write(s)
        setlists.append(s)
        sortSetlists()
        return s
    }

    public func updateSetlist(_ s: SetlistMeta) {
        guard let i = setlists.firstIndex(where: { $0.id == s.id }) else { return }
        setlists[i] = s
        write(s)
    }

    public func setSlot(_ position: Int, of setlistID: UUID, to patchID: UUID?) {
        guard var s = setlist(setlistID), s.slots.indices.contains(position) else { return }
        s.slots[position] = patchID
        updateSetlist(s)
    }

    /// Applies a drag-and-drop: a library patch replaces the slot; another slot swaps places with it.
    @discardableResult
    public func apply(_ item: DragItem, to position: Int, in setlistID: UUID) -> Bool {
        switch item {
        case .patch(let id):
            guard patch(id) != nil else { return false }
            setSlot(position, of: setlistID, to: id)
        case .slot(let from):
            swapSlots(from, position, in: setlistID)
        }
        return true
    }

    public func swapSlots(_ a: Int, _ b: Int, in setlistID: UUID) {
        guard var s = setlist(setlistID), s.slots.indices.contains(a), s.slots.indices.contains(b) else { return }
        s.slots.swapAt(a, b)
        updateSetlist(s)
    }

    /// Puts the blank patch into the 4 memories of a bank (1-based).
    @discardableResult
    public func resetBankToBlank(_ bank: Int, in setlistID: UUID) -> Bool {
        guard let d = ensureBlankPatch(), var s = setlist(setlistID), (1...SlotLayout.banks).contains(bank) else { return false }
        for m in 1...SlotLayout.memories { s.slots[SlotLayout.position(bank: bank, memory: m)] = d.id }
        updateSetlist(s)
        return true
    }

    /// `bank` is 1-based. The label is also remembered for the bank's content, so loading the same bank again restores it.
    public func setBankDescription(_ text: String, bank: Int, in setlistID: UUID) {
        guard var s = setlist(setlistID), (1...SlotLayout.banks).contains(bank) else { return }
        let t = text.trimmingCharacters(in: .whitespaces)
        guard s.bankDescriptions[bank - 1] != t else { return }
        s.bankDescriptions[bank - 1] = t
        updateSetlist(s)
        if let key = bankKey(s, bank: bank) {
            var labels = info.bankLabels ?? [:]
            labels[key] = t.isEmpty ? nil : t
            info.bankLabels = labels.isEmpty ? nil : labels
            saveInfo()
        }
    }

    /// Identifies a bank by the content of its 4 memories (patch hashes, memory 1 first); nil if any slot has no patch.
    func bankKey(_ s: SetlistMeta, bank: Int) -> String? {
        let hashes = (1...SlotLayout.memories).compactMap { m in patch(s.slots[SlotLayout.position(bank: bank, memory: m)])?.meta.hash }
        return hashes.count == SlotLayout.memories ? hashes.joined(separator: ",") : nil
    }

    /// The remembered label for a bank with this content: the stored one, else any existing setlist's bank that has it.
    func rememberedLabel(forKey key: String) -> String? {
        if let l = info.bankLabels?[key], !l.isEmpty { return l }
        for s in setlists {
            for bank in 1...SlotLayout.banks where !s.bankDescriptions[bank - 1].isEmpty && bankKey(s, bank: bank) == key {
                return s.bankDescriptions[bank - 1]
            }
        }
        return nil
    }

    public func renameSetlist(_ id: UUID, to name: String) {
        guard var s = setlist(id) else { return }
        s.name = name
        updateSetlist(s)
        sortSetlists()
    }

    public func duplicateSetlist(_ id: UUID) {
        guard let s = setlist(id) else { return }
        createSetlist(name: s.name + " copy", slots: s.slots, header: s.header, tags: s.tags, bankDescriptions: s.bankDescriptions)
    }

    public func deleteSetlist(_ id: UUID) {
        try? fm.removeItem(at: setlistsDir.appendingPathComponent("\(id.uuidString).setlist"))
        setlists.removeAll { $0.id == id }
    }

    private func sortSetlists() { setlists.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }

    private func write(_ s: SetlistMeta) {
        let dir = setlistsDir.appendingPathComponent("\(s.id.uuidString).setlist")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try encoder.encode(s).write(to: dir.appendingPathComponent("setlist.json"), options: .atomic)
        } catch { lastError = "Could not save setlist: \(error.localizedDescription)" }
    }

    // MARK: Import / export

    public func makeImportPlan(from url: URL) throws -> ImportPlan {
        let file = try USRFile(data: Data(contentsOf: url))
        return ImportPlan(fileName: url.lastPathComponent, file: file, known: knownHashes)
    }

    /// Adds the chosen new patches (position → name) and optionally creates a setlist mirroring the file.
    @discardableResult
    public func commit(_ plan: ImportPlan, names: [Int: String], icons: [Int: InstrumentIcon] = [:], setlistName: String?) -> SetlistMeta? {
        var byHash = knownHashes
        for slot in plan.newSlots {
            guard let name = names[slot.position] else { continue }   // skipped by the user
            let p = addPatch(record: plan.file.patches[slot.position], name: name, source: plan.fileName, icon: icons[slot.position])
            byHash[slot.hash] = p.id
        }
        guard let setlistName else { return nil }
        let slots: [UUID?] = plan.slots.map { byHash[$0.hash] }
        var created = createSetlist(name: setlistName, slots: slots, header: plan.file.header)
        // A bank that was labelled before (same 4 patches) gets its label back.
        var labelled = false
        for bank in 1...SlotLayout.banks {
            if let key = bankKey(created, bank: bank), let label = rememberedLabel(forKey: key) {
                created.bankDescriptions[bank - 1] = label; labelled = true
            }
        }
        if labelled { updateSetlist(created) }
        return created
    }

    public func buildFile(for setlistID: UUID) throws -> USRFile {
        guard let s = setlist(setlistID) else { throw LibraryError.missingPatch }
        guard isComplete(s) else { throw LibraryError.incomplete(USRFile.patchCount - filledCount(s)) }
        guard s.header.count == USRFile.headerSize else { throw LibraryError.missingPatch }
        let records = try s.slots.map { id -> Data in
            guard let p = patch(id) else { throw LibraryError.missingPatch }
            return p.data
        }
        return USRFile(header: s.header, patches: records)
    }

    public func export(setlistID: UUID, to url: URL) throws {
        try buildFile(for: setlistID).serialized().write(to: url, options: .atomic)
    }
}
