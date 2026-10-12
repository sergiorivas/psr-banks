import SwiftUI
import AppKit

extension Color {
    /// A colour that follows the window's light/dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light)
        }))
    }
}

enum Theme {
    static let canvas = Color(light: Color(red: 0.95, green: 0.95, blue: 0.965), dark: Color(red: 0.07, green: 0.075, blue: 0.09))
    static let panel = Color(light: .white, dark: Color(red: 0.12, green: 0.125, blue: 0.145))
    static let well = Color(light: Color(red: 0.93, green: 0.935, blue: 0.95), dark: Color(red: 0.09, green: 0.095, blue: 0.11))
    static let stroke = Color(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.10))
    static let accent = Color(light: Color(red: 0.0, green: 0.42, blue: 0.82), dark: Color(red: 0.36, green: 0.68, blue: 1.0))
    static let good = Color(light: Color(red: 0.10, green: 0.55, blue: 0.30), dark: Color(red: 0.35, green: 0.82, blue: 0.55))
    static let warn = Color(light: Color(red: 0.80, green: 0.45, blue: 0.0), dark: Color(red: 1.0, green: 0.70, blue: 0.30))
    static let muted = Color.secondary

    /// One hue per bank so a bank is recognisable across the app.
    static let bankHues: [Color] = [
        Color(hue: 0.58, saturation: 0.65, brightness: 0.85), Color(hue: 0.47, saturation: 0.60, brightness: 0.75),
        Color(hue: 0.35, saturation: 0.55, brightness: 0.72), Color(hue: 0.14, saturation: 0.70, brightness: 0.88),
        Color(hue: 0.07, saturation: 0.70, brightness: 0.90), Color(hue: 0.98, saturation: 0.60, brightness: 0.88),
        Color(hue: 0.83, saturation: 0.50, brightness: 0.85), Color(hue: 0.72, saturation: 0.50, brightness: 0.88),
    ]
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme? { self == .system ? nil : (self == .light ? .light : .dark) }
    var icon: String { self == .system ? "circle.lefthalf.filled" : (self == .light ? "sun.max" : "moon") }
}

struct Chip: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.stroke))
    }
}
