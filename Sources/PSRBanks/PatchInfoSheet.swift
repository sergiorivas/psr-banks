import SwiftUI
import PSRCore

/// Everything we know about one patch: library data, all decoded settings, and the raw bytes.
struct PatchInfoSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let patchID: UUID

    var body: some View {
        VStack(spacing: 0) {
            if let p = store.patch(patchID) {
                let d = PatchDetails(record: p.data)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(p)
                        libraryCard(p)
                        voicesCard(d)
                        otherCard(d)
                        rawCard(p)
                    }.padding(20)
                }
            } else {
                Text("This patch is no longer in the library.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(14)
        }
        .frame(width: 640, height: 700)
        .background(Theme.canvas)
    }

    // MARK: Sections

    private func header(_ p: Patch) -> some View {
        HStack(spacing: 12) {
            PatchTitle(patch: p, nameSize: 20, iconEditable: true)
            Spacer()
            if p.meta.splitOn { Chip(text: "SPLIT", color: Theme.warn) }
            if p.meta.dualOn { Chip(text: "DUAL", color: Theme.good) }
        }
    }

    private func libraryCard(_ p: Patch) -> some View {
        let sets = store.setlists.filter { $0.slots.contains(p.id) }
        return section("Library") {
            row("Name", p.name)
            row("Default patch", store.defaultPatchID == p.id ? "Yes ★" : "No")
            row("Icon", p.icon.title + (p.hasCustomIcon ? " (set by you; automatic would be \(p.inferredIcon.title))" : " (automatic, from the main voice)"))
            row("Tags", p.meta.tags.isEmpty ? "—" : p.meta.tags.map { "#\($0)" }.joined(separator: "  "))
            row("Used in", sets.isEmpty ? "no setlist" : sets.map { "\($0.name) (\($0.slots.filter { $0 == p.id }.count)×)" }.joined(separator: ", "))
            row("Added", p.meta.createdAt.formatted(date: .abbreviated, time: .shortened))
            row("Imported from", p.meta.source ?? "—")
            row("File", store.patchFolderURL(p.id).path, mono: true)
            HStack {
                Spacer().frame(width: 142)
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.patchFolderURL(p.id).appendingPathComponent("record.bin")]) }
                    .controlSize(.small)
            }
            row("Identity (SHA-256)", String(p.meta.hash.prefix(32)) + "…", mono: true)
        }
    }

    private func voicesCard(_ d: PatchDetails) -> some View {
        section("Voices") {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach([d.main, d.split, d.dual], id: \.role) { v in
                        HStack(spacing: 6) {
                            Text(v.role).font(.system(size: 12, weight: .bold))
                            if let on = v.on { Chip(text: on ? "ON" : "OFF", color: on ? Theme.good : .secondary) }
                        }
                    }
                }
                Divider().gridCellColumns(4)
                GridRow {
                    label("Voice")
                    ForEach([d.main, d.split, d.dual], id: \.role) { v in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(v.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                            Text("No. \(v.number)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                grid("Octave", [d.main, d.split, d.dual]) { $0.octave > 0 ? "+\($0.octave)" : "\($0.octave)" }
                grid("Volume", [d.main, d.split, d.dual]) { "\($0.volume)" }
                grid("Pan", [d.main, d.split, d.dual]) { PatchDetails.panName($0.pan) }
                grid("Reverb", [d.main, d.split, d.dual]) { "\($0.reverb)" }
                grid("Chorus", [d.main, d.split, d.dual]) { "\($0.chorus)" }
                grid("Attack", [d.main, d.split, d.dual]) { $0.attack.map(String.init) ?? "—" }
                grid("Release", [d.main, d.split, d.dual]) { $0.release.map(String.init) ?? "—" }
                grid("Cutoff", [d.main, d.split, d.dual]) { $0.cutoff.map(String.init) ?? "—" }
                grid("Resonance", [d.main, d.split, d.dual]) { $0.resonance.map(String.init) ?? "—" }
            }
            Text("Settings of a voice that is switched off are still stored and shown here. The split voice has no envelope bytes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func otherCard(_ d: PatchDetails) -> some View {
        section("Other settings") {
            row("Split point", "\(PatchDetails.noteName(d.splitPoint))  (MIDI \(d.splitPoint))"
                + (d.splitPointBytesAgree ? "" : "  ⚠︎ the two stored copies differ"))
            row("Transpose", d.transpose > 0 ? "+\(d.transpose)" : "\(d.transpose)")
            row("Pitch-bend range", "\(d.pitchBendRange)")
            row("Touch response", ["Off", "1 Soft", "2 Medium", "3 Hard"][safe: d.touchResponse] ?? "code \(d.touchResponse)")
            row("Reverb level", "\(d.reverbLevel)")
            row("Harmony", "\(d.harmonyOn ? "On" : "Off") · \(d.harmonyName) · volume \(d.harmonyVolume)")
            row("DSP 1", "\(d.dsp1On ? "On" : "Off") · type \(d.dsp1Type) · \(PatchDetails.dspPartName(d.dsp1Part, isDSP1: true))")
            row("DSP 2", "\(d.dsp2On ? "On" : "Off") · type code \(d.dsp2TypeRaw) · \(PatchDetails.dspPartName(d.dsp2Part, isDSP1: false))")
            row("Style", d.styleNumber.map { "No. \($0) · volume \(d.styleVolume ?? 0)" } ?? "none saved (voices only)")
            row("Head bytes", d.head.map { String(format: "%02X", $0) }.joined(separator: " "), mono: true)
            Text("Not decoded yet: tuning, arpeggio, master EQ, reverb and chorus type, DSP knobs. "
                 + "Reverb level and harmony on/off are inferred from one bank. The DSP 2 type is shown as the stored code because its numbering isn’t confirmed. Only some harmony and DSP part names are confirmed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func rawCard(_ p: Patch) -> some View {
        DisclosureGroup {
            let bytes = [UInt8](p.data)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<(bytes.count + 15) / 16, id: \.self) { row in
                    let slice = bytes[row * 16..<min(row * 16 + 16, bytes.count)]
                    Text(String(format: "%03d  ", row * 16) + slice.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }.padding(.top, 6)
        } label: { Text("Raw data · \(p.data.count) bytes").font(.headline) }
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }

    // MARK: Helpers

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(v).font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13)).textSelection(.enabled)
            Spacer(minLength: 0)
        }.font(.system(size: 13))
    }

    private func label(_ s: String) -> some View { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }

    @ViewBuilder private func grid(_ title: String, _ voices: [PatchDetails.Voice], _ value: @escaping (PatchDetails.Voice) -> String) -> some View {
        GridRow {
            label(title)
            ForEach(voices, id: \.role) { v in Text(value(v)).font(.system(size: 12, design: .rounded)).monospacedDigit() }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
