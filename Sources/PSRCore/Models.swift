import Foundation

public struct PatchMeta: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var hash: String
    public var mainVoice: Int
    public var splitOn: Bool
    public var dualOn: Bool
    public var createdAt: Date
    public var source: String?
    public var tags: [String] = []
    /// Manual choice; nil means "automatic" (inferred from the main voice).
    public var icon: InstrumentIcon?
}

extension PatchMeta {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        hash = try c.decode(String.self, forKey: .hash)
        mainVoice = try c.decode(Int.self, forKey: .mainVoice)
        splitOn = try c.decode(Bool.self, forKey: .splitOn)
        dualOn = try c.decode(Bool.self, forKey: .dualOn)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []   // libraries from v1 have no tags
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)).flatMap { $0 }.flatMap(InstrumentIcon.init(rawValue:))
    }
}

/// One memory slot's worth of data (145 bytes) plus metadata. Stored on disk as a folder
/// `<id>.patch/` containing `record.bin` and `meta.json`.
public struct Patch: Identifiable, Hashable {
    public var meta: PatchMeta
    public let data: Data
    public var id: UUID { meta.id }
    public var name: String { meta.name }
    public var info: PatchInfo { PatchInfo(record: data) }
    public var inferredIcon: InstrumentIcon { InstrumentIcon.infer(voice: meta.mainVoice) }
    public var icon: InstrumentIcon { meta.icon ?? inferredIcon }
    public var hasCustomIcon: Bool { meta.icon != nil }
}

public struct SetlistMeta: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    /// 32 entries in file order (memory-major, see `SlotLayout`); nil = still empty.
    public var slots: [UUID?]
    /// The first 464 bytes of the `.USR` file this setlist is exported into.
    public var header: Data
    public var tags: [String] = []
    /// Short phrase per bank (8 entries, bank 1 first), e.g. "Salsa". Empty string = none.
    public var bankDescriptions: [String] = Array(repeating: "", count: SlotLayout.banks)

    public var filledCount: Int { slots.compactMap { $0 }.count }
    public var isComplete: Bool { filledCount == USRFile.patchCount }
}

extension SetlistMeta {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        slots = try c.decode([UUID?].self, forKey: .slots)
        header = try c.decode(Data.self, forKey: .header)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        let d = try c.decodeIfPresent([String].self, forKey: .bankDescriptions) ?? []
        bankDescriptions = Array((d + Array(repeating: "", count: SlotLayout.banks)).prefix(SlotLayout.banks))
    }
}

/// Result of comparing an imported `.USR` with the library.
public struct ImportPlan {
    public struct Slot: Identifiable {
        public var id: Int { position }
        public let position: Int
        public let hash: String
        public let info: PatchInfo
        /// Library patch with identical bytes, if any.
        public let existing: UUID?
        /// True for the first occurrence of a hash within the file.
        public let isFirstOccurrence: Bool
    }

    public let fileName: String
    public let file: USRFile
    public let slots: [Slot]

    public init(fileName: String, file: USRFile, known: [String: UUID]) {
        self.fileName = fileName
        self.file = file
        var seen = Set<String>()
        slots = file.patches.enumerated().map { i, rec in
            let h = PatchInfo.hash(of: rec)
            let first = seen.insert(h).inserted
            return Slot(position: i, hash: h, info: PatchInfo(record: rec), existing: known[h], isFirstOccurrence: first)
        }
    }

    /// Distinct patches that are not in the library yet.
    public var newSlots: [Slot] { slots.filter { $0.existing == nil && $0.isFirstOccurrence } }
    public var knownCount: Int { slots.filter { $0.existing != nil }.count }
    public var duplicateCount: Int { slots.filter { !$0.isFirstOccurrence }.count }
}
