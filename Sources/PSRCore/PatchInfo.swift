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
    public let styleNumber: Int?      // 1-based; nil when the patch carries no style
    public let styleVolume: Int?
    public let transpose: Int         // semitones, stored +12
    public let pitchBendRange: Int
    public let touchResponse: Int     // 1 Soft, 2 Medium, 3 Hard
    public let harmonyOn: Bool        // probable, from one bank
    public let reverbLevel: Int       // probable, from one bank
    public let dsp1Part: Int          // 0 = Main Voice
    public let dsp2Part: Int          // 2 = Keyboard
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
        styleNumber = hasStyle ? Int(b[2]) + 1 : nil
        styleVolume = hasStyle ? Int(b[7]) : nil
        transpose = Int(b[62]) - 12
        pitchBendRange = Int(b[43])
        touchResponse = Int(b[44])
        reverbLevel = Int(b[45])
        harmonyOn = b[47] == 0x7F
        dsp1Part = Int(b[91]); dsp2Part = Int(b[87])
        head = Array(b[0..<4])
    }

    /// Yamaha naming: middle C (MIDI 60) is C3.
    public static func noteName(_ midi: Int) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return "\(names[midi % 12])\(midi / 12 - 2)"
    }

    public static func panName(_ v: Int) -> String { v == 64 ? "C" : (v < 64 ? "L\(64 - v)" : "R\(v - 64)") }

    /// Names for 1...26 follow the keyboard's list; only Octave (5) and Echo 1/32 (26) are confirmed against real banks.
    public var harmonyName: String {
        let base = ["Duet", "Trio", "Block", "Country", "Octave"]
        let rates = ["1/4", "1/6", "1/8", "1/12", "1/16", "1/24", "1/32"]
        switch harmonyType {
        case 1...5: return base[harmonyType - 1]
        case 6...12: return "Trill " + rates[harmonyType - 6]
        case 13...19: return "Tremolo " + rates[harmonyType - 13]
        case 20...26: return "Echo " + rates[harmonyType - 20]
        default: return "Type \(harmonyType)"
        }
    }

    public static func dspPartName(_ v: Int, isDSP1: Bool) -> String {
        if isDSP1 && v == 0 { return "Main Voice" }
        if !isDSP1 && v == 2 { return "Keyboard" }
        return "part code \(v)"
    }
}
