import Foundation

/// The pictogram shown for a patch. Inferred from the main voice; a patch can override it.
public enum InstrumentIcon: String, Codable, CaseIterable, Identifiable {
    case piano, organ, organLead, guitar, guitarLead, acousticGuitar, bass, ukulele
    case synth, synthLead, drums, percussion, strings, brass, other
    // Added later
    case electricPiano, woodwind, choir, accordion, harp, sfx, synthPad, mallets

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .piano: return "Piano"
        case .organ: return "Organ"
        case .organLead: return "Organ lead"
        case .guitar: return "Guitar"
        case .guitarLead: return "Guitar lead"
        case .acousticGuitar: return "Acoustic guitar"
        case .bass: return "Bass"
        case .ukulele: return "Ukulele"
        case .synth: return "Synth"
        case .synthLead: return "Synth lead"
        case .drums: return "Drums"
        case .percussion: return "Percussion"
        case .strings: return "Strings"
        case .brass: return "Brass"
        case .other: return "Other"
        case .electricPiano: return "Electric piano"
        case .woodwind: return "Woodwind"
        case .choir: return "Choir / voice"
        case .accordion: return "Accordion"
        case .harp: return "Harp"
        case .sfx: return "Sound effect"
        case .synthPad: return "Synth pad"
        case .mallets: return "Mallets"
        }
    }

    /// Voice groups of the PSR-E483 voice list (data list pages 4–11).
    enum Category { case piano, organ, guitarBass, strings, brass, woodwind, world, synth, percDrums, arpeggio, xgLite }

    static func category(of voice: Int) -> Category {
        switch voice {
        case ..<43: return .piano
        case 43..<81: return .organ
        case 81..<124: return .guitarBass
        case 124..<159: return .strings
        case 159..<187: return .brass
        case 187..<214: return .woodwind
        case 214..<256: return .world
        case 256..<310: return .synth
        case 310..<363: return .percDrums
        case 363..<403: return .arpeggio
        default: return .xgLite
        }
    }

    /// Best guess for a voice number, using its list group and name.
    public static func infer(voice: Int) -> InstrumentIcon {
        let name = VoiceCatalog.name(for: voice).lowercased()
        let words = Set(name.split(whereSeparator: { !$0.isLetter }).map(String.init))
        let cat = category(of: voice)
        func has(_ needles: String...) -> Bool { needles.contains { name.contains($0) } }

        if voice >= 812 { return .sfx }                       // XGlite sound effects (fret noise … fireworks)
        if has("uke") { return .ukulele }
        if has("kit") || words.contains("tom") || has("cymbal") || has("synth drum") { return .drums }
        if has("choir", "voice", "vox", "ooh", "aah") { return .choir }
        if cat == .woodwind || has("sax", "flute", "clarinet", "oboe", "bassoon", "piccolo", "recorder", "ocarina", "english horn") { return .woodwind }
        if cat == .world || cat == .arpeggio {
            return has("banjo", "mandolin") ? .acousticGuitar : .other
        }
        if has("bass") { return .bass }
        if cat == .guitarBass || has("guitar", "banjo", "mandolin") {
            if has("nylon", "steel", "acoustic", "12 string", "12-string", "classic", "banjo", "mandolin") { return .acousticGuitar }
            if has("distortion", "overdriven", "lead", "feedback", "wah") { return .guitarLead }
            return .guitar
        }
        if has("harmonica", "accordion", "bandoneon", "musette", "harmonium") { return .accordion }
        if has("harp") { return .harp }
        if cat == .organ || has("organ") { return has("lead", "solo") ? .organLead : .organ }
        if has("electric piano", "e.piano", "clavi", "cp80", "rhodes", "wurli", "electric grand") { return .electricPiano }
        if cat == .piano || has("piano", "harpsichord") { return .piano }
        if cat == .strings || has("string", "violin", "cello", "viola") { return .strings }
        if cat == .brass || has("trumpet", "trombone", "horn", "tuba", "brass") { return .brass }
        if cat == .synth || has("synth", "saw", "square") {
            if has("pad") { return .synthPad }
            return has("lead") ? .synthLead : .synth
        }
        if has("vibe", "marimba", "xylo", "glock", "bell", "tubular", "celesta", "steel drum", "kalimba", "music box", "santur", "bonang") { return .mallets }
        if cat == .percDrums || has("percussion", "taiko", "agogo", "cowbell", "tambourine", "conga", "bongo", "timpani") { return .percussion }
        if has("drum") { return .drums }
        if has("lead") { return .synthLead }
        return .other
    }
}
