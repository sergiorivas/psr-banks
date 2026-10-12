import SwiftUI
import PSRCore

extension InstrumentIcon {
    /// Two-tone gradient per instrument family.
    var colors: [Color] {
        switch self {
        case .piano, .organ, .organLead, .electricPiano: return [Color(red: 0.25, green: 0.52, blue: 0.95), Color(red: 0.16, green: 0.33, blue: 0.78)]
        case .guitar, .guitarLead, .acousticGuitar, .bass, .ukulele: return [Color(red: 0.98, green: 0.62, blue: 0.22), Color(red: 0.85, green: 0.38, blue: 0.12)]
        case .synth, .synthLead, .synthPad: return [Color(red: 0.66, green: 0.42, blue: 0.95), Color(red: 0.44, green: 0.25, blue: 0.78)]
        case .drums, .percussion, .mallets: return [Color(red: 0.95, green: 0.38, blue: 0.40), Color(red: 0.76, green: 0.20, blue: 0.30)]
        case .strings, .harp: return [Color(red: 0.30, green: 0.75, blue: 0.50), Color(red: 0.14, green: 0.55, blue: 0.40)]
        case .brass: return [Color(red: 0.96, green: 0.80, blue: 0.25), Color(red: 0.80, green: 0.58, blue: 0.10)]
        case .woodwind: return [Color(red: 0.22, green: 0.74, blue: 0.80), Color(red: 0.10, green: 0.52, blue: 0.62)]
        case .choir: return [Color(red: 0.94, green: 0.48, blue: 0.72), Color(red: 0.78, green: 0.28, blue: 0.56)]
        case .accordion: return [Color(red: 0.86, green: 0.52, blue: 0.38), Color(red: 0.66, green: 0.32, blue: 0.24)]
        case .sfx: return [Color(red: 0.42, green: 0.70, blue: 0.92), Color(red: 0.26, green: 0.48, blue: 0.74)]
        case .other: return [Color(red: 0.55, green: 0.60, blue: 0.68), Color(red: 0.38, green: 0.43, blue: 0.52)]
        }
    }
}

/// Rounded tile with the instrument pictogram.
struct InstrumentBadge: View {
    let icon: InstrumentIcon
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: icon.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            InstrumentGlyph(icon: icon).padding(size * 0.13)
        }
        .frame(width: size, height: size)
        .help(icon.title)
        .accessibilityLabel(icon.title)
    }
}

/// White pictogram drawn on a 24 × 24 grid. "Lead" variants shrink the base shape and add a sparkle.
struct InstrumentGlyph: View {
    let icon: InstrumentIcon

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            var ctx = context
            ctx.scaleBy(x: s, y: s)
            ctx.drawLayer { layer in Self.draw(icon, in: &layer) }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Drawing

    private static let ink = GraphicsContext.Shading.color(.white.opacity(0.97))

    private static func star(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: c)
        return p
    }

    private static func draw(_ icon: InstrumentIcon, in ctx: inout GraphicsContext) {
        switch icon {
        case .piano: piano(&ctx)
        case .organ: pipes(&ctx)
        case .organLead: lead(&ctx) { pipes(&$0) }
        case .guitar: electric(&ctx)
        case .guitarLead: lead(&ctx) { electric(&$0) }
        case .acousticGuitar: acoustic(&ctx)
        case .bass: bass(&ctx)
        case .ukulele: ukulele(&ctx)
        case .synth: synth(&ctx)
        case .synthLead: lead(&ctx) { synth(&$0) }
        case .drums: drum(&ctx)
        case .percussion: congas(&ctx)
        case .strings: violin(&ctx)
        case .brass: trumpet(&ctx)
        case .other: note(&ctx)
        case .electricPiano: badged(&ctx, mark: .bolt) { piano(&$0) }
        case .woodwind: flute(&ctx)
        case .choir: choir(&ctx)
        case .accordion: accordion(&ctx)
        case .harp: harp(&ctx)
        case .sfx: burst(&ctx)
        case .synthPad: pad(&ctx)
        case .mallets: mallets(&ctx)
        }
    }

    private enum Mark { case star, bolt }

    private static func lead(_ ctx: inout GraphicsContext, base: (inout GraphicsContext) -> Void) { badged(&ctx, mark: .star, base: base) }

    private static func bolt() -> Path {
        var p = Path()
        let pts = [(19.6, 0.6), (15.4, 6.6), (18.0, 6.6), (16.4, 11.0), (22.2, 4.4), (19.4, 4.4), (21.4, 0.6)]
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    /// Draws `base` slightly smaller and adds a mark in the top-right corner.
    private static func badged(_ ctx: inout GraphicsContext, mark: Mark, base: (inout GraphicsContext) -> Void) {
        var c = ctx
        c.translateBy(x: 0, y: 4.6)
        c.scaleBy(x: 0.8, y: 0.8)
        base(&c)
        ctx.fill(mark == .star ? star(CGPoint(x: 19, y: 5.2), 4.4) : bolt(), with: ink)
    }

    private static func cut(_ ctx: inout GraphicsContext, _ path: Path) {
        var c = ctx
        c.blendMode = .destinationOut
        c.fill(path, with: .color(.black))
    }

    private static func cutStroke(_ ctx: inout GraphicsContext, _ path: Path, _ w: CGFloat) {
        var c = ctx
        c.blendMode = .destinationOut
        c.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> Path { var p = Path(); p.move(to: a); p.addLine(to: b); return p }
    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    private static func piano(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 2.5, y: 5.5, width: 19, height: 13), cornerRadius: 2), with: ink)
        let w = 19.0 / 5
        for i in 1...4 { cutStroke(&ctx, line(CGPoint(x: 2.5 + w * Double(i), y: 5.5), CGPoint(x: 2.5 + w * Double(i), y: 18.5)), 0.7) }
        for i in [1, 2, 4] { cut(&ctx, Path(roundedRect: CGRect(x: 2.5 + w * Double(i) - 1.15, y: 5.5, width: 2.3, height: 8), cornerRadius: 0.6)) }
    }

    private static func pipes(_ ctx: inout GraphicsContext) {
        let heights: [CGFloat] = [8, 12, 16, 12, 8]
        for (i, h) in heights.enumerated() {
            ctx.fill(Path(roundedRect: CGRect(x: 3.0 + CGFloat(i) * 3.9, y: 19 - h, width: 2.9, height: h), cornerRadius: 1.2), with: ink)
        }
        ctx.fill(Path(roundedRect: CGRect(x: 2.2, y: 19.6, width: 19.6, height: 1.8), cornerRadius: 0.9), with: ink)
    }

    private static func guitarBody(_ ctx: inout GraphicsContext, lower: (CGFloat, CGFloat, CGFloat, CGFloat), upper: (CGFloat, CGFloat, CGFloat, CGFloat),
                                   neck: CGRect, head: CGRect) {
        ctx.fill(oval(lower.0, lower.1, lower.2, lower.3), with: ink)
        ctx.fill(oval(upper.0, upper.1, upper.2, upper.3), with: ink)
        ctx.fill(Path(neck), with: ink)
        ctx.fill(Path(roundedRect: head, cornerRadius: 0.9), with: ink)
    }

    private static func electric(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(40)); c.translateBy(x: -12, y: -12)
        guitarBody(&c, lower: (12, 16.6, 5.3, 4.3), upper: (12, 12.0, 3.7, 3.3), neck: CGRect(x: 11.1, y: 3.4, width: 1.8, height: 9), head: CGRect(x: 10.5, y: 0.9, width: 3, height: 3.6))
        cut(&c, Path(CGRect(x: 10.2, y: 14.4, width: 3.6, height: 0.9)))
        cut(&c, Path(CGRect(x: 10.2, y: 16.9, width: 3.6, height: 0.9)))
    }

    private static func acoustic(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(40)); c.translateBy(x: -12, y: -12)
        guitarBody(&c, lower: (12, 16.2, 5.9, 5.0), upper: (12, 11.4, 4.3, 3.6), neck: CGRect(x: 11.0, y: 3.4, width: 2, height: 8), head: CGRect(x: 10.4, y: 0.9, width: 3.2, height: 3.6))
        cut(&c, Path(ellipseIn: CGRect(x: 10.0, y: 14.2, width: 4, height: 4)))
    }

    private static func bass(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(-18)); c.translateBy(x: -12, y: -12)
        guitarBody(&c, lower: (12, 18, 4.6, 3.6), upper: (12, 14.2, 3.2, 2.9), neck: CGRect(x: 11.2, y: 3.4, width: 1.6, height: 11), head: CGRect(x: 10.3, y: 0.8, width: 3.4, height: 3.8))
        for y in [6.2, 8.4, 10.6, 12.6] { cutStroke(&c, line(CGPoint(x: 11.3, y: y), CGPoint(x: 12.7, y: y)), 0.5) }
        cut(&c, Path(CGRect(x: 10.4, y: 16.2, width: 3.2, height: 0.8)))
        cut(&c, Path(CGRect(x: 10.4, y: 18.2, width: 3.2, height: 0.8)))
    }

    private static func ukulele(_ ctx: inout GraphicsContext) {
        guitarBody(&ctx, lower: (12, 16.2, 5.4, 5.0), upper: (12, 11.2, 3.8, 3.2), neck: CGRect(x: 11.1, y: 3.6, width: 1.8, height: 7), head: CGRect(x: 10.5, y: 1.4, width: 3, height: 3))
        cut(&ctx, Path(ellipseIn: CGRect(x: 10.3, y: 14.4, width: 3.4, height: 3.4)))
        cutStroke(&ctx, line(CGPoint(x: 9.2, y: 20), CGPoint(x: 14.8, y: 20)), 0.7)
    }

    private static func synth(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 2, y: 6.5, width: 20, height: 11.5), cornerRadius: 2), with: ink)
        for x in [6.0, 9.6, 13.2] { cut(&ctx, Path(ellipseIn: CGRect(x: x - 1.1, y: 8.1, width: 2.2, height: 2.2))) }
        cut(&ctx, Path(CGRect(x: 17, y: 8.3, width: 3, height: 1.2)))
        cutStroke(&ctx, line(CGPoint(x: 3.3, y: 11.9), CGPoint(x: 20.7, y: 11.9)), 0.8)
        for i in 1...6 { cutStroke(&ctx, line(CGPoint(x: 3.3 + 2.9 * Double(i), y: 12.2), CGPoint(x: 3.3 + 2.9 * Double(i), y: 17)), 0.7) }
    }

    private static func drum(_ ctx: inout GraphicsContext) {
        var body = Path()
        body.move(to: CGPoint(x: 4.5, y: 10)); body.addLine(to: CGPoint(x: 4.5, y: 17.4))
        body.addQuadCurve(to: CGPoint(x: 19.5, y: 17.4), control: CGPoint(x: 12, y: 22.2))
        body.addLine(to: CGPoint(x: 19.5, y: 10)); body.closeSubpath()
        ctx.fill(body, with: ink)
        ctx.fill(oval(12, 10, 7.5, 2.8), with: ink)
        cutStroke(&ctx, { var p = Path(); p.addEllipse(in: CGRect(x: 4.5, y: 7.2, width: 15, height: 5.6)); return p }(), 0.8)
        for x in [8.0, 12.0, 16.0] { cutStroke(&ctx, line(CGPoint(x: x, y: 14), CGPoint(x: x, y: 18.2)), 0.7) }
        var sticks = Path(); sticks.move(to: CGPoint(x: 5.2, y: 1.6)); sticks.addLine(to: CGPoint(x: 11.2, y: 7))
        sticks.move(to: CGPoint(x: 18.8, y: 1.6)); sticks.addLine(to: CGPoint(x: 12.8, y: 7))
        cutStroke(&ctx, sticks, 3.0)
        ctx.stroke(sticks, with: ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private static func conga(_ ctx: inout GraphicsContext, cx: CGFloat, top: CGFloat, rx: CGFloat, bottom: CGFloat) {
        var b = Path()
        b.move(to: CGPoint(x: cx - rx, y: top)); b.addLine(to: CGPoint(x: cx + rx, y: top))
        b.addLine(to: CGPoint(x: cx + rx * 0.62, y: bottom)); b.addQuadCurve(to: CGPoint(x: cx - rx * 0.62, y: bottom), control: CGPoint(x: cx, y: bottom + 1.6))
        b.closeSubpath()
        ctx.fill(b, with: ink)
        ctx.fill(oval(cx, top, rx, 1.6), with: ink)
        cutStroke(&ctx, { var p = Path(); p.addEllipse(in: CGRect(x: cx - rx, y: top - 1.6, width: rx * 2, height: 3.2)); return p }(), 0.7)
        cutStroke(&ctx, line(CGPoint(x: cx - rx * 0.85, y: top + (bottom - top) * 0.45), CGPoint(x: cx + rx * 0.85, y: top + (bottom - top) * 0.45)), 0.8)
    }

    private static func congas(_ ctx: inout GraphicsContext) {
        conga(&ctx, cx: 7.6, top: 6.6, rx: 4.1, bottom: 19)
        conga(&ctx, cx: 16.4, top: 9.4, rx: 4.1, bottom: 19)
    }

    private static func violin(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(22)); c.translateBy(x: -12, y: -12)
        c.fill(oval(12, 16.2, 5.0, 4.4), with: ink)
        c.fill(oval(12, 11.6, 3.7, 3.2), with: ink)
        c.fill(Path(CGRect(x: 11.2, y: 3.4, width: 1.6, height: 8)), with: ink)
        c.fill(oval(12, 2.6, 1.5, 1.5), with: ink)
        cutStroke(&c, line(CGPoint(x: 10.2, y: 12.8), CGPoint(x: 10.2, y: 16.8)), 0.7)
        cutStroke(&c, line(CGPoint(x: 13.8, y: 12.8), CGPoint(x: 13.8, y: 16.8)), 0.7)
        let bow = line(CGPoint(x: 3.2, y: 20.6), CGPoint(x: 20.8, y: 11.4))
        cutStroke(&ctx, bow, 2.6)
        ctx.stroke(bow, with: ink, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
    }

    private static func trumpet(_ ctx: inout GraphicsContext) {
        var bell = Path()
        bell.move(to: CGPoint(x: 14.6, y: 12.8)); bell.addQuadCurve(to: CGPoint(x: 21.8, y: 7.4), control: CGPoint(x: 18, y: 12.2))
        bell.addLine(to: CGPoint(x: 21.8, y: 18.6)); bell.addQuadCurve(to: CGPoint(x: 14.6, y: 14.2), control: CGPoint(x: 18, y: 14.8))
        bell.closeSubpath()
        ctx.fill(bell, with: ink)
        ctx.stroke(line(CGPoint(x: 4.2, y: 13.5), CGPoint(x: 15, y: 13.5)), with: ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        ctx.fill(oval(2.7, 13.5, 1.5, 1.5), with: ink)
        var loop = Path()
        loop.move(to: CGPoint(x: 6.2, y: 13.5)); loop.addLine(to: CGPoint(x: 6.2, y: 11))
        loop.addQuadCurve(to: CGPoint(x: 7.4, y: 9.8), control: CGPoint(x: 6.2, y: 9.8)); loop.addLine(to: CGPoint(x: 11.3, y: 9.8))
        loop.addQuadCurve(to: CGPoint(x: 12.5, y: 11), control: CGPoint(x: 12.5, y: 9.8)); loop.addLine(to: CGPoint(x: 12.5, y: 13.5))
        ctx.stroke(loop, with: ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        for x in [7.7, 9.4, 11.1] { ctx.stroke(line(CGPoint(x: x, y: 6.4), CGPoint(x: x, y: 13.2)), with: ink, style: StrokeStyle(lineWidth: 1.2, lineCap: .round)) }
    }

    private static func flute(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(-38)); c.translateBy(x: -12, y: -12)
        c.fill(Path(roundedRect: CGRect(x: 1.8, y: 10.5, width: 20.4, height: 3.0), cornerRadius: 1.5), with: ink)
        c.fill(Path(roundedRect: CGRect(x: 3.8, y: 9.4, width: 2.2, height: 1.4), cornerRadius: 0.6), with: ink)
        for x in [9.0, 11.8, 14.6, 17.4] { cut(&c, Path(ellipseIn: CGRect(x: x - 0.6, y: 11.4, width: 1.2, height: 1.2))) }
        cutStroke(&c, line(CGPoint(x: 7.4, y: 10.6), CGPoint(x: 7.4, y: 13.4)), 0.6)
    }

    private static func person(_ ctx: inout GraphicsContext, cx: CGFloat, head: CGFloat, shoulder: CGFloat, scale: CGFloat) {
        ctx.fill(oval(cx, head, 3.2 * scale, 3.3 * scale), with: ink)
        var b = Path()
        b.move(to: CGPoint(x: cx - 6.8 * scale, y: 21)); b.addQuadCurve(to: CGPoint(x: cx, y: shoulder), control: CGPoint(x: cx - 6.8 * scale, y: shoulder))
        b.addQuadCurve(to: CGPoint(x: cx + 6.8 * scale, y: 21), control: CGPoint(x: cx + 6.8 * scale, y: shoulder)); b.closeSubpath()
        ctx.fill(b, with: ink)
    }

    private static func choir(_ ctx: inout GraphicsContext) {
        person(&ctx, cx: 5.2, head: 9.6, shoulder: 14.4, scale: 0.62)
        person(&ctx, cx: 18.8, head: 9.6, shoulder: 14.4, scale: 0.62)
        // gap around the front singer so the three read as separate
        var halo = Path(); halo.addEllipse(in: CGRect(x: 8.6, y: 3.6, width: 6.8, height: 7.0)); halo.addEllipse(in: CGRect(x: 4.6, y: 11.4, width: 14.8, height: 12))
        cutStroke(&ctx, halo, 1.8)
        person(&ctx, cx: 12, head: 7.6, shoulder: 12.8, scale: 1.0)
        cut(&ctx, Path(ellipseIn: CGRect(x: 10.9, y: 7.6, width: 2.2, height: 1.7)))
    }

    private static func accordion(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(roundedRect: CGRect(x: 2.2, y: 5.2, width: 4.2, height: 13.6), cornerRadius: 1.4), with: ink)
        ctx.fill(Path(roundedRect: CGRect(x: 17.6, y: 5.2, width: 4.2, height: 13.6), cornerRadius: 1.4), with: ink)
        ctx.fill(Path(CGRect(x: 6.8, y: 6.6, width: 10.4, height: 10.8)), with: ink)
        for i in 0..<5 { cutStroke(&ctx, line(CGPoint(x: 8.4 + 2.05 * Double(i), y: 6.6), CGPoint(x: 8.4 + 2.05 * Double(i), y: 17.4)), 0.8) }
        for y in [8.4, 11.0, 13.6, 16.0] { cut(&ctx, Path(ellipseIn: CGRect(x: 3.4, y: y - 0.7, width: 1.4, height: 1.4))) }
        for y in [8.6, 12.0, 15.4] { cut(&ctx, Path(CGRect(x: 18.8, y: y, width: 1.8, height: 1.2))) }
    }

    private static func harp(_ ctx: inout GraphicsContext) {
        var frame = Path()
        frame.move(to: CGPoint(x: 4.5, y: 21)); frame.addLine(to: CGPoint(x: 4.5, y: 4))
        frame.addQuadCurve(to: CGPoint(x: 20, y: 9.5), control: CGPoint(x: 15, y: 2.6))
        frame.addLine(to: CGPoint(x: 20, y: 21)); frame.closeSubpath()
        ctx.stroke(frame, with: ink, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        for i in 0..<5 {
            let x = 7.8 + 2.5 * Double(i)
            let top = 4.2 + (x - 4.5) * 0.17 + (i == 0 ? 0 : 0.3)
            ctx.stroke(line(CGPoint(x: x, y: top + 1.2), CGPoint(x: x, y: 20.6)), with: ink, style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
        }
    }

    private static func burst(_ ctx: inout GraphicsContext) {
        var p = Path()
        for i in 0..<16 {
            let r: Double = i % 2 == 0 ? 10.4 : 4.6
            let a = Double(i) * .pi / 8 - .pi / 2
            let pt = CGPoint(x: 12 + r * cos(a), y: 12 + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        ctx.fill(p, with: ink)
        cut(&ctx, Path(ellipseIn: CGRect(x: 9.6, y: 9.6, width: 4.8, height: 4.8)))
    }

    private static func pad(_ ctx: inout GraphicsContext) {
        for (i, y) in [6.4, 12.0, 17.6].enumerated() {
            var p = Path()
            for step in 0...40 {
                let x = 2.5 + 19.0 * Double(step) / 40
                let yy = y + 2.1 * sin(Double(step) / 40 * 2 * .pi * 1.5 + Double(i) * 1.1)
                if step == 0 { p.move(to: CGPoint(x: x, y: yy)) } else { p.addLine(to: CGPoint(x: x, y: yy)) }
            }
            ctx.stroke(p, with: ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private static func mallets(_ ctx: inout GraphicsContext) {
        var c = ctx
        c.translateBy(x: 12, y: 12); c.rotate(by: .degrees(-10)); c.translateBy(x: -12, y: -12)
        for (i, h) in [13.0, 11.4, 9.8, 8.2].enumerated() {
            c.fill(Path(roundedRect: CGRect(x: 2.6 + CGFloat(i) * 3.5, y: 21 - h, width: 2.7, height: h), cornerRadius: 1.2), with: ink)
        }
        let stick = line(CGPoint(x: 13.6, y: 14.5), CGPoint(x: 21.4, y: 4.6))
        cutStroke(&c, stick, 3.2)
        c.stroke(stick, with: ink, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
        c.fill(oval(21.0, 4.4, 2.1, 2.1), with: ink)
    }

    private static func note(_ ctx: inout GraphicsContext) {
        var head = ctx
        head.translateBy(x: 8.6, y: 17.4); head.rotate(by: .degrees(-22)); head.translateBy(x: -8.6, y: -17.4)
        head.fill(oval(8.6, 17.4, 3.6, 2.7), with: ink)
        ctx.fill(Path(CGRect(x: 11.4, y: 4.6, width: 1.5, height: 13)), with: ink)
        var flag = Path()
        flag.move(to: CGPoint(x: 12.9, y: 4.6)); flag.addQuadCurve(to: CGPoint(x: 18.6, y: 10.6), control: CGPoint(x: 13.2, y: 8.6))
        flag.addQuadCurve(to: CGPoint(x: 12.9, y: 8.2), control: CGPoint(x: 17.2, y: 7.8)); flag.closeSubpath()
        ctx.fill(flag, with: ink)
    }
}

/// Popover grid for choosing an icon; `nil` means "automatic".
struct IconPicker: View {
    let current: InstrumentIcon
    let automatic: InstrumentIcon
    let isCustom: Bool
    let choose: (InstrumentIcon?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instrument icon").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 4), spacing: 10) {
                ForEach(InstrumentIcon.allCases) { ic in
                    Button { choose(ic == automatic && !isCustom ? nil : ic); dismiss() } label: {
                        VStack(spacing: 4) {
                            InstrumentBadge(icon: ic, size: 38)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: ic == current ? 2.5 : 0).padding(-3))
                            Text(ic.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Button { choose(nil); dismiss() } label: { Label("Automatic (\(automatic.title))", systemImage: "wand.and.stars") }
                    .disabled(!isCustom)
                Spacer()
                if isCustom { Text("Set by you").font(.caption).foregroundStyle(.secondary) } else { Text("Chosen from the voice").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(16).frame(width: 396)
    }
}

/// A badge that opens the picker when clicked.
struct IconButton: View {
    @EnvironmentObject var store: LibraryStore
    let patch: Patch
    var size: CGFloat = 30
    @State private var open = false

    var body: some View {
        Button { open = true } label: { InstrumentBadge(icon: patch.icon, size: size) }
            .buttonStyle(.plain)
            .help("\(patch.icon.title) — click to change")
            .popover(isPresented: $open, arrowEdge: .trailing) {
                IconPicker(current: patch.icon, automatic: patch.inferredIcon, isCustom: patch.hasCustomIcon) { store.setIcon($0, forPatch: patch.id) }
            }
    }
}

/// Menus can only show images, so each badge is rendered once to a coloured bitmap.
@MainActor
enum IconImages {
    private static var cache: [InstrumentIcon: NSImage] = [:]

    static func image(_ icon: InstrumentIcon) -> NSImage {
        if let hit = cache[icon] { return hit }
        let renderer = ImageRenderer(content: InstrumentBadge(icon: icon, size: 18))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false
        cache[icon] = img
        return img
    }
}

/// Menu row: coloured icon preview + title.
struct IconLabel: View {
    let icon: InstrumentIcon
    let title: String
    var body: some View {
        Label { Text(title) } icon: { Image(nsImage: IconImages.image(icon)).renderingMode(.original) }
    }
}

/// "Icon ▸" submenu for context menus: shows the current icon next to the title and a preview beside every choice.
struct IconMenu: View {
    @EnvironmentObject var store: LibraryStore
    let patch: Patch
    var body: some View {
        Menu {
            Button { store.setIcon(nil, forPatch: patch.id) } label: {
                IconLabel(icon: patch.inferredIcon, title: "Automatic (\(patch.inferredIcon.title))" + (patch.hasCustomIcon ? "" : "  ✓"))
            }
            .disabled(!patch.hasCustomIcon)
            Divider()
            ForEach(InstrumentIcon.allCases) { ic in
                Button { store.setIcon(ic, forPatch: patch.id) } label: {
                    IconLabel(icon: ic, title: ic.title + (patch.icon == ic && patch.hasCustomIcon ? "  ✓" : ""))
                }
            }
        } label: {
            IconLabel(icon: patch.icon, title: "Icon: \(patch.icon.title)")
        }
    }
}

/// Contact sheet of all icons (used by `--render-icons`).
enum IconSheet {
    @MainActor static func render(to path: String) {
        let view = HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(92), spacing: 6), count: 6), spacing: 12) {
                    ForEach(InstrumentIcon.allCases) { ic in
                        VStack(spacing: 4) {
                            InstrumentBadge(icon: ic, size: 64)
                            Text(ic.title).font(.system(size: 10)).foregroundStyle(dark ? Color.white : Color.black)
                            Image(nsImage: IconImages.image(ic)).renderingMode(.original)
                        }
                    }
                }
                .padding(16)
                .background(dark ? Color(white: 0.12) : Color(white: 0.96))
            }
        }
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
