import Foundation
import CryptoKit

/// Read-only view over the bytes of one 145-byte patch. Offsets include the 4-byte head.
public struct PatchInfo: Equatable {
    public let mainVoice: Int
    public let splitVoice: Int
    public let dualVoice: Int
    public let splitOn: Bool
    public let dualOn: Bool
    public let splitPoint: Int
    public let hasStyle: Bool

    public init(record r: Data) {
        let b = Data(r)
        func voice(_ o: Int) -> Int { (Int(b[o]) << 8 | Int(b[o + 1])) + 1 }   // stored 0-based
        mainVoice = voice(12)
        splitVoice = voice(24)
        dualVoice = voice(32)
        splitOn = b[23] == 0x7F
        dualOn = b[31] == 0x7F
        splitPoint = Int(b[4])
        hasStyle = b[6..<12] != Data(repeating: 0xFF, count: 6)
    }

    public static func hash(of record: Data) -> String {
        SHA256.hash(data: record).map { String(format: "%02x", $0) }.joined()
    }

    /// Default library name for a patch, e.g. "Overdriven Guitar", "Strings + Finger Bass (split)".
    public var suggestedName: String {
        var name = VoiceCatalog.name(for: mainVoice)
        if dualOn { name += " + " + VoiceCatalog.name(for: dualVoice) }
        if splitOn { name += " / " + VoiceCatalog.name(for: splitVoice) + " (split)" }
        return name
    }
}

public enum VoiceCatalog {
    private static let names: [Int: String] = {
        guard let url = Resources.url("voices_e483", "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var out: [Int: String] = [:]
        for (k, v) in obj { if let n = Int(k), let name = v["name"] as? String { out[n] = name } }
        return out
    }()

    public static func name(for voice: Int) -> String { names[voice] ?? "Voice \(voice)" }
}

/// Everything we can currently read out of a patch. Offsets are inside the 145-byte patch (head included).
public struct PatchDetails {
    public struct Voice {
        public let role: String
        public let on: Bool?          // nil for the main voice (always on)
        public let number: Int
        public let octave: Int
        public let volume: Int
        public let pan: Int
        public let reverb: Int
        public let chorus: Int
        public let attack: Int?       // split has no envelope bytes
        public let release: Int?
        public let cutoff: Int?
        public let resonance: Int?
        public var name: String { VoiceCatalog.name(for: number) }
    }

    public let main: Voice, split: Voice, dual: Voice
    public let splitPoint: Int
    public let splitPointBytesAgree: Bool
    public let harmonyType: Int
    public let harmonyVolume: Int
    public let dsp1On: Bool, dsp2On: Bool
    public let dsp1Type: Int          // 1-based number as shown on the keyboard
    public let dsp2TypeRaw: Int       // encoding not confirmed
    public let hasStyle: Bool
    public let head: [UInt8]

    public init(record r: Data) {
        let b = [UInt8](r)
        func u16(_ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }
        func s8(_ o: Int) -> Int { Int(Int8(bitPattern: b[o])) }
        func voice(_ role: String, on: Bool?, at o: Int, env: Bool) -> Voice {
            Voice(role: role, on: on, number: u16(o) + 1, octave: s8(o + 2), volume: Int(b[o + 3]), pan: Int(b[o + 4]),
                  reverb: Int(b[o + 5]), chorus: Int(b[o + 6]),
                  attack: env ? Int(b[o + 7]) : nil, release: env ? Int(b[o + 8]) : nil,
                  cutoff: env ? Int(b[o + 9]) : nil, resonance: env ? Int(b[o + 10]) : nil)
        }
        main = voice("Main", on: nil, at: 12, env: true)
        split = voice("Split", on: b[23] == 0x7F, at: 24, env: false)
        dual = voice("Dual", on: b[31] == 0x7F, at: 32, env: true)
        splitPoint = Int(b[4])
        splitPointBytesAgree = b[4] == b[5]
        harmonyType = Int(b[48]); harmonyVolume = Int(b[49])
        dsp2On = b[88] == 0x7F; dsp1On = b[89] == 1
        dsp2TypeRaw = Int(b[82]); dsp1Type = Int(b[90]) + 1
        hasStyle = PatchInfo(record: r).hasStyle
        head = Array(b[0..<4])
    }

    /// Yamaha naming: middle C (MIDI 60) is C3.
    public static func noteName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[midi % 12])\(midi / 12 - 2)"
    }

    public static func panName(_ v: Int) -> String { v == 64 ? "C" : (v < 64 ? "L\(64 - v)" : "R\(v - 64)") }

    public var harmonyName: String {
        switch harmonyType {
        case 1: return "Duet"
        case 2: return "Trio"
        case 5: return "Octave"
        default: return "Type \(harmonyType)"
        }
    }
}
