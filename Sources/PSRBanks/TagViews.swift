import SwiftUI
import PSRCore

/// Wraps its children onto several lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in result.origins.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var origins: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), origins)
    }
}

struct TagBadge: View {
    let tag: String
    var active = false
    var compact = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(tag)")
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: compact ? 9 : 10.5, weight: .medium, design: .rounded))
        .padding(.horizontal, compact ? 5 : 7).padding(.vertical, compact ? 1.5 : 2.5)
        .background(active ? Theme.accent : Theme.accent.opacity(0.13), in: Capsule())
        .foregroundStyle(active ? Color.white : Theme.accent)
    }
}

/// Small read-only row of tags (at most `limit`, then "+n").
struct TagRow: View {
    let tags: [String]
    var limit = 4
    var compact = false
    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(limit), id: \.self) { TagBadge(tag: $0, compact: compact) }
                if tags.count > limit { Text("+\(tags.count - limit)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Add/remove tags, with suggestions from tags already used in the library.
struct TagEditor: View {
    @EnvironmentObject var store: LibraryStore
    let title: String
    let tags: [String]
    let onChange: ([String]) -> Void
    @State private var text = ""

    private var suggestions: [String] {
        store.tagCounts.map(\.name).filter { !Tags.contains(tags, $0) && (text.isEmpty || $0.localizedCaseInsensitiveContains(text)) }.prefix(10).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if tags.isEmpty {
                Text("No tags yet").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout { ForEach(tags, id: \.self) { t in TagBadge(tag: t, onRemove: { onChange(tags.filter { $0 != t }) }) } }
            }
            TextField("Add tags, separated by commas", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            if !suggestions.isEmpty {
                Text("Existing tags").font(.caption).foregroundStyle(.secondary)
                FlowLayout {
                    ForEach(suggestions, id: \.self) { s in
                        Button { onChange(tags + [s]) } label: { TagBadge(tag: s) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14).frame(width: 300)
    }

    private func add() {
        let new = Tags.parse(text)
        guard !new.isEmpty else { return }
        onChange(tags + new)
        text = ""
    }
}

/// Button that shows the tags and opens the editor in a popover.
struct TagButton: View {
    let title: String
    let tags: [String]
    let onChange: ([String]) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "tag").font(.system(size: 11))
                Text(tags.isEmpty ? "Add tag" : "Edit tags").font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Theme.well, in: Capsule())
            .overlay(Capsule().stroke(Theme.stroke))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) { TagEditor(title: title, tags: tags, onChange: onChange) }
    }
}

/// Instrument icon + the patch name with its main voice always shown underneath.
struct PatchTitle: View {
    let patch: Patch
    var nameSize: CGFloat = 13
    var iconEditable = false
    var rename: RenameConfig?
    var body: some View {
        HStack(spacing: 10) {
            if iconEditable { IconButton(patch: patch, size: nameSize + 17) } else { InstrumentBadge(icon: patch.icon, size: nameSize + 17) }
            VStack(alignment: .leading, spacing: 2) {
                if let rename { RenameableName(text: patch.name, font: .system(size: nameSize, weight: .semibold), config: rename) }
                else { Text(patch.name).font(.system(size: nameSize, weight: .semibold)).lineLimit(1) }
                Label {
                    Text("\(patch.meta.mainVoice) · \(VoiceCatalog.name(for: patch.meta.mainVoice))").lineLimit(1)
                } icon: { Image(systemName: "pianokeys") }
                    .font(.system(size: nameSize - 2)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Sheet for editing one patch's tags from anywhere (e.g. a setlist slot's context menu).
struct PatchTagSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let patchID: UUID

    var body: some View {
        VStack(spacing: 0) {
            if let p = store.patch(patchID) {
                PatchTitle(patch: p, nameSize: 14).frame(maxWidth: .infinity, alignment: .leading).padding([.horizontal, .top], 14)
                TagEditor(title: "Tags", tags: p.meta.tags) { store.setTags($0, forPatch: patchID) }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding([.horizontal, .bottom], 14)
        }
        .frame(width: 330)
    }
}
