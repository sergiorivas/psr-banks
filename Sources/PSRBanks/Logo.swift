import SwiftUI

/// App mark: a grid of memory pads above a short piano keyboard. Mirrors tools/make_icon.swift.
struct LogoMark: View {
    var size: CGFloat = 36

    var body: some View {
        let r = size * 0.225
        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.42), Color(red: 0.08, green: 0.62, blue: 0.66)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { ctx, sz in
                let w = sz.width, h = sz.height
                let padW = w * 0.15, gap = w * 0.04
                let gridW = padW * 4 + gap * 3
                let x0 = (w - gridW) / 2, y0 = h * 0.14
                let lit: Set<Int> = [0, 2, 5, 6, 9, 11]
                for row in 0..<3 {
                    for col in 0..<4 {
                        let rect = CGRect(x: x0 + CGFloat(col) * (padW + gap), y: y0 + CGFloat(row) * (padW * 0.70 + w * 0.035), width: padW, height: padW * 0.70)
                        let on = lit.contains(row * 4 + col)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: padW * 0.22),
                                 with: .color(on ? Color(red: 1.0, green: 0.78, blue: 0.28) : Color.white.opacity(0.22)))
                    }
                }
                let keysTop = h * 0.60, keysH = h * 0.24, kw = gridW / 7
                for i in 0..<7 {
                    let rect = CGRect(x: x0 + CGFloat(i) * kw + 0.5, y: keysTop, width: kw - 1.5, height: keysH)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: kw * 0.18), with: .color(.white.opacity(0.94)))
                }
                for i in [0, 1, 3, 4, 5] {
                    let rect = CGRect(x: x0 + CGFloat(i + 1) * kw - kw * 0.2, y: keysTop, width: kw * 0.4, height: keysH * 0.6)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: kw * 0.1), with: .color(Color(red: 0.07, green: 0.09, blue: 0.22)))
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.06, y: size * 0.03)
    }
}
