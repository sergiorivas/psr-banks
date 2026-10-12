import Foundation

public enum USRError: LocalizedError {
    case wrongSize(Int)
    case badMagic
    case badMarkers

    public var errorDescription: String? {
        switch self {
        case .wrongSize(let n): return "Unexpected file size (\(n) bytes, expected \(USRFile.fileSize)). Is this a PSR-E483 user file?"
        case .badMagic: return "This is not a PSR-E483 user file (missing \"PSR-E483UserFile\" signature)."
        case .badMarkers: return "The file structure is damaged (missing PSR end markers)."
        }
    }
}

/// A PSR-E483 `.USR` backup.
///
/// Layout (reverse engineered, see ANALYSIS.md):
/// - `0x000` header (464 bytes): signature, version, ten "No Data" name slots, constants
/// - `0x1D0` checksum: UInt32 LE = sum of all bytes from `0x1D4` to end-of-file, modulo 256
/// - `0x1D4` marker `PSR\x03`
/// - `0x1D8` 32 patches × 145 bytes, memory-major order
/// - `0x13F8` marker `PSR\x03` (file ends at `0x13FC`)
public struct USRFile: Equatable {
    public static let magic = Data("PSR-E483UserFile".utf8)
    public static let headerSize = 0x1D0
    public static let startMarkerOffset = 0x1D4
    public static let patchesOffset = 0x1D8
    public static let patchSize = 145
    public static let patchCount = 32
    public static let endMarkerOffset = patchesOffset + patchSize * patchCount
    public static let fileSize = endMarkerOffset + 4
    public static let marker = Data([0x50, 0x53, 0x52, 0x03])

    /// Bytes `0x000..<0x1D0` (everything before the checksum).
    public var header: Data
    /// 32 records of 145 bytes in file order (see `SlotLayout`).
    public var patches: [Data]
    /// Checksum as read from the file (nil when the value was built in memory).
    public private(set) var storedChecksum: UInt32?

    public init(header: Data, patches: [Data]) {
        precondition(header.count == Self.headerSize && patches.count == Self.patchCount && patches.allSatisfy { $0.count == Self.patchSize })
        self.header = header
        self.patches = patches
        self.storedChecksum = nil
    }

    public init(data raw: Data) throws {
        let data = Data(raw)   // normalise indices
        guard data.count == Self.fileSize else { throw USRError.wrongSize(data.count) }
        guard data.prefix(Self.magic.count) == Self.magic else { throw USRError.badMagic }
        guard data[Self.startMarkerOffset..<Self.startMarkerOffset + 4] == Self.marker,
              data[Self.endMarkerOffset..<Self.endMarkerOffset + 4] == Self.marker else { throw USRError.badMarkers }
        header = Data(data[0..<Self.headerSize])
        patches = (0..<Self.patchCount).map { i in
            let s = Self.patchesOffset + i * Self.patchSize
            return Data(data[s..<s + Self.patchSize])
        }
        let c = data[Self.headerSize..<Self.headerSize + 4]
        storedChecksum = c.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    /// Sum of bytes from the start marker to the end of the file, modulo 256.
    public var computedChecksum: UInt32 {
        var sum = Self.marker.reduce(0) { $0 + Int($1) } * 2
        for p in patches { sum += p.reduce(0) { $0 + Int($1) } }
        return UInt32(sum & 0xFF)
    }

    public var checksumIsValid: Bool { storedChecksum.map { $0 == computedChecksum } ?? true }

    public func serialized() -> Data {
        var out = Data(capacity: Self.fileSize)
        out.append(header)
        let c = computedChecksum
        out.append(contentsOf: [UInt8(c & 0xFF), UInt8((c >> 8) & 0xFF), UInt8((c >> 16) & 0xFF), UInt8((c >> 24) & 0xFF)])
        out.append(Self.marker)
        for p in patches { out.append(p) }
        out.append(Self.marker)
        return out
    }

    /// The header of a factory-fresh-looking file, used when a setlist is built from scratch.
    public static var defaultHeader: Data {
        guard let url = Resources.url("default_header", "bin"),
              let d = try? Data(contentsOf: url), d.count == headerSize else {
            fatalError("default_header.bin missing from bundle")
        }
        return d
    }

    /// Human-readable description of the file layout, for the "file structure" view.
    public struct Section: Identifiable {
        public let id = UUID()
        public let name: String
        public let offset: Int
        public let size: Int
        public let detail: String
    }

    public var sections: [Section] {
        let version = String(decoding: header[16..<24].filter { $0 != 0 }, as: UTF8.self)
        let ok = checksumIsValid ? "valid" : "MISMATCH (stored \(storedChecksum.map(String.init) ?? "-"), computed \(computedChecksum))"
        return [
            Section(name: "Header", offset: 0, size: Self.headerSize, detail: "Signature PSR-E483UserFile, version \(version), ten song-name slots"),
            Section(name: "Checksum", offset: Self.headerSize, size: 4, detail: "Sum of bytes 0x1D4…end mod 256 — \(ok)"),
            Section(name: "Start marker", offset: Self.startMarkerOffset, size: 4, detail: "PSR\\x03"),
            Section(name: "Registration memory", offset: Self.patchesOffset, size: Self.patchSize * Self.patchCount,
                    detail: "32 patches × 145 bytes: 8 banks × 4 memories, stored Memory 1 of banks 1–8, then Memory 2 …"),
            Section(name: "End marker", offset: Self.endMarkerOffset, size: 4, detail: "PSR\\x03"),
        ]
    }
}

/// Mapping between (bank, memory) and the position of a patch in the file.
/// The file is memory-major: positions 0–7 are Memory 1 of banks 1–8, 8–15 are Memory 2, and so on.
public enum SlotLayout {
    public static let banks = 8
    public static let memories = 4
    public static func position(bank: Int, memory: Int) -> Int { (memory - 1) * banks + (bank - 1) }
    public static func bank(at position: Int) -> Int { position % banks + 1 }
    public static func memory(at position: Int) -> Int { position / banks + 1 }
    public static func label(at position: Int) -> String { "Bank \(bank(at: position)) · Memory \(memory(at: position))" }
}
