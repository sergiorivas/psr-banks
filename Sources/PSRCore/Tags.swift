import Foundation

/// Free-form labels attached to patches and setlists. Matching ignores case and a leading "#".
public enum Tags {
    public static func clean(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasPrefix("#") { t.removeFirst() }
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.isEmpty ? nil : String(t.prefix(32))
    }

    public static func key(_ tag: String) -> String { tag.lowercased() }

    public static func contains(_ tags: [String], _ tag: String) -> Bool {
        tags.contains { key($0) == key(tag) }
    }

    /// Cleans, drops duplicates (case-insensitively, first spelling wins) and keeps the order.
    public static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap(clean).filter { seen.insert(key($0)).inserted }
    }

    /// Accepts "rock, ballad  #slow" and returns the individual tags.
    public static func parse(_ text: String) -> [String] {
        normalized(text.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" }).map(String.init))
    }

    public static func matches(_ tags: [String], all required: Set<String>) -> Bool {
        required.allSatisfy { contains(tags, $0) }
    }
}

public struct TagCount: Identifiable, Hashable {
    public let name: String
    public let patches: Int
    public let setlists: Int
    public var id: String { Tags.key(name) }
    public var total: Int { patches + setlists }
}

public enum Search {
    /// Every word typed must appear in the haystack (case/diacritic-insensitive).
    public static func matches(_ query: String, in haystack: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        return words.allSatisfy { w in haystack.contains { $0.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
    }
}

extension Patch {
    public func matches(search: String, tags required: Set<String> = []) -> Bool {
        let i = info
        let voices = [i.mainVoice] + (i.splitOn ? [i.splitVoice] : []) + (i.dualOn ? [i.dualVoice] : [])
        return Tags.matches(meta.tags, all: required)
            && Search.matches(search, in: [name, icon.title] + voices.map(VoiceCatalog.name(for:)) + meta.tags)
    }
}

extension SetlistMeta {
    public func matches(search: String, tags required: Set<String> = []) -> Bool {
        Tags.matches(tags, all: required) && Search.matches(search, in: [name] + tags)
    }
}

/// What is being dragged inside the app: a patch from the library, or the content of a setlist slot.
public enum DragItem: Equatable {
    case patch(UUID)
    case slot(Int)

    public var payload: String {
        switch self {
        case .patch(let id): return "psr-patch:\(id.uuidString)"
        case .slot(let p): return "psr-slot:\(p)"
        }
    }

    public init?(payload: String) {
        if payload.hasPrefix("psr-patch:"), let id = UUID(uuidString: String(payload.dropFirst(10))) { self = .patch(id) }
        else if payload.hasPrefix("psr-slot:"), let p = Int(payload.dropFirst(9)), (0..<USRFile.patchCount).contains(p) { self = .slot(p) }
        else { return nil }
    }
}
