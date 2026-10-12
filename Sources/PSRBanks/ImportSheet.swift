import SwiftUI
import PSRCore

struct ImportSheet: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let plan: ImportPlan

    @State private var names: [Int: String] = [:]
    @State private var chosen: Set<Int> = []
    @State private var icons: [Int: InstrumentIcon] = [:]   // user overrides; the rest are inferred
    @State private var iconPopover: Int?
    @State private var saveSetlist = true
    @State private var setlistName = ""
    @State private var showStructure = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Card { map }
                    newPatches
                    Card { setlistOption }
                    structure
                }
                .padding(22)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 780)
        .background(Theme.canvas)
        .onAppear {
            for s in plan.newSlots { names[s.position] = s.info.suggestedName }
            chosen = Set(plan.newSlots.map { $0.position })
            setlistName = (plan.fileName as NSString).deletingPathExtension
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import \(plan.fileName)").font(.system(size: 22, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                Chip(text: "\(plan.newSlots.count) new", color: Theme.accent)
                Chip(text: "\(plan.knownCount) already in library", color: Theme.good)
                if plan.duplicateCount > 0 { Chip(text: "\(plan.duplicateCount) repeated in file", color: .secondary) }
                Chip(text: plan.file.checksumIsValid ? "checksum OK" : "checksum mismatch", color: plan.file.checksumIsValid ? Theme.good : Theme.warn)
            }
        }
    }

    private var map: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is in this file").font(.headline)
            VStack(spacing: 6) {
                ForEach(1...SlotLayout.banks, id: \.self) { bank in
                    HStack(spacing: 6) {
                        Text("Bank \(bank)").font(.system(size: 11, weight: .semibold, design: .rounded)).frame(width: 50, alignment: .leading)
                        ForEach(1...SlotLayout.memories, id: \.self) { memory in
                            let slot = plan.slots[SlotLayout.position(bank: bank, memory: memory)]
                            MapCell(slot: slot, libraryName: store.patch(slot.existing)?.name,
                                    icon: store.patch(slot.existing)?.icon ?? icons[slot.position] ?? InstrumentIcon.infer(voice: slot.info.mainVoice))
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                legend(Theme.accent, "new")
                legend(Theme.good, "already in library")
                legend(.secondary, "same as an earlier slot")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
    }

    @ViewBuilder private var newPatches: some View {
        if plan.newSlots.isEmpty {
            Card {
                Label("Every patch in this file is already in your library.", systemImage: "checkmark.seal")
                    .foregroundStyle(Theme.good)
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("New patches to add").font(.headline)
                        Spacer()
                        Button("All") { chosen = Set(plan.newSlots.map { $0.position }) }.buttonStyle(.link)
                        Button("None") { chosen = [] }.buttonStyle(.link)
                    }
                    ForEach(plan.newSlots) { s in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { chosen.contains(s.position) },
                                                     set: { if $0 { chosen.insert(s.position) } else { chosen.remove(s.position) } }))
                                .labelsHidden()
                            Button { iconPopover = s.position } label: { InstrumentBadge(icon: icons[s.position] ?? InstrumentIcon.infer(voice: s.info.mainVoice), size: 34) }
                                .buttonStyle(.plain).help("Change icon")
                                .popover(isPresented: Binding(get: { iconPopover == s.position }, set: { if !$0 { iconPopover = nil } })) {
                                    IconPicker(current: icons[s.position] ?? InstrumentIcon.infer(voice: s.info.mainVoice),
                                               automatic: InstrumentIcon.infer(voice: s.info.mainVoice), isCustom: icons[s.position] != nil) { icons[s.position] = $0 }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Name", text: Binding(get: { names[s.position] ?? "" }, set: { names[s.position] = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                Text("\(SlotLayout.label(at: s.position)) · main voice \(s.info.mainVoice) \(VoiceCatalog.name(for: s.info.mainVoice))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if s.info.splitOn { Chip(text: "SPLIT", color: Theme.warn) }
                            if s.info.dualOn { Chip(text: "DUAL", color: Theme.good) }
                        }
                    }
                }
            }
        }
    }

    private var setlistOption: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $saveSetlist) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Also save this file as a setlist").font(.headline)
                    Text("Keeps all 32 slots in their original positions so you can edit and re-export it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if saveSetlist {
                TextField("Setlist name", text: $setlistName).textFieldStyle(.roundedBorder)
                if plan.newSlots.contains(where: { !chosen.contains($0.position) }) {
                    Label("Some new patches are unchecked, so those slots will start out empty in the setlist.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private var structure: some View {
        DisclosureGroup(isExpanded: $showStructure) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.file.sections) { sec in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "0x%04X", sec.offset)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
                        Text("\(sec.size) B").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sec.name).font(.system(size: 12, weight: .semibold))
                            Text(sec.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding(.top, 8)
        } label: { Text("File structure").font(.headline) }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }

    private var footer: some View {
        HStack {
            Text(summary).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Import") { commit() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty && !saveSetlist)
        }
        .padding(16)
    }

    private var summary: String {
        var parts: [String] = []
        if !chosen.isEmpty { parts.append("\(chosen.count) patch\(chosen.count == 1 ? "" : "es")") }
        if saveSetlist { parts.append("1 setlist") }
        return parts.isEmpty ? "Nothing selected" : "Will add " + parts.joined(separator: " and ")
    }

    private func commit() {
        let picked = names.filter { chosen.contains($0.key) }
        let name = setlistName.trimmingCharacters(in: .whitespaces)
        let created = store.commit(plan, names: picked, icons: icons.filter { chosen.contains($0.key) }, setlistName: saveSetlist ? (name.isEmpty ? plan.fileName : name) : nil)
        dismiss()
        if let created { state.selection = .setlist(created.id) } else { state.selection = .patches }
    }
}

struct MapCell: View {
    let slot: ImportPlan.Slot
    let libraryName: String?
    let icon: InstrumentIcon

    var body: some View {
        let color: Color = slot.existing != nil ? Theme.good : (slot.isFirstOccurrence ? Theme.accent : .secondary)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 6) {
        InstrumentBadge(icon: icon, size: 22)
        VStack(alignment: .leading, spacing: 2) {
            Text(libraryName ?? slot.info.suggestedName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            HStack(spacing: 4) {
                Text("\(slot.info.mainVoice) · \(VoiceCatalog.name(for: slot.info.mainVoice))")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if slot.info.splitOn { Chip(text: "S", color: Theme.warn) }
                if slot.info.dualOn { Chip(text: "D", color: Theme.good) }
            }
        }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.13), in: shape)
        .overlay(shape.stroke(color.opacity(0.45)))
        .help("\(SlotLayout.label(at: slot.position))")
    }
}
