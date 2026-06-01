import SwiftUI

/// First-class panel for OmniVoice's "voice design" / instruct mode.
/// Updates app.settings.instruct as the user toggles attribute chips.
struct VoiceDesignPanel: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var settingsObserver: AppSettings

    init() {
        // Workaround: ObservedObject(wrappedValue:) requires a value at
        // init. We bind to a fresh AppSettings here, then in body we
        // mirror the AppState's settings instance.
        self._settingsObserver = ObservedObject(wrappedValue: AppSettings())
    }

    var body: some View {
        VoiceDesignBody(settings: app.settings)
    }
}

private struct VoiceDesignBody: View {
    @ObservedObject var settings: AppSettings

    // Selected attributes (string set, joined with ", " into settings.instruct)
    @State private var selected: Set<String> = []
    @State private var customAttribute: String = ""

    private static let groups: [(label: String, options: [String])] = [
        ("Gender",     ["male", "female"]),
        ("Age",        ["child", "teenager", "young adult", "adult", "middle-aged", "elderly"]),
        ("Pitch",      ["very low", "low", "medium", "high", "very high"]),
        ("Style",      ["whisper", "shout", "calm", "angry", "happy", "sad", "soft"]),
        ("English accent",
                       ["American accent", "British accent", "Australian accent",
                        "Indian accent", "Scottish accent"]),
        ("Chinese dialect",
                       ["四川话", "陕西话", "粤语", "东北话", "台湾腔"]),
    ]

    // Saved presets
    @AppStorage("voiceDesignPresets") private var presetsRaw: String = ""
    @State private var savedPresets: [Preset] = []
    @State private var newPresetName: String = ""

    struct Preset: Codable, Identifiable, Hashable {
        var id: UUID
        var name: String
        var value: String
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Voice design", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                Text("Build a voice from attributes — no reference audio needed. Combine across categories freely.")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(Self.groups, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.label).font(.callout).bold()
                        FlowLayout(spacing: 6) {
                            ForEach(group.options, id: \.self) { opt in
                                Chip(text: opt,
                                     selected: selected.contains(opt),
                                     onTap: { toggle(opt) })
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom attribute").font(.callout).bold()
                    HStack {
                        TextField("e.g. raspy, slightly nervous", text: $customAttribute)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            let v = customAttribute.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !v.isEmpty {
                                selected.insert(v)
                                customAttribute = ""
                                sync()
                            }
                        }
                        .disabled(customAttribute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !selected.isEmpty {
                    HStack {
                        Text("Active:")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(joined)
                            .font(.callout)
                            .foregroundStyle(.tint)
                        Spacer()
                        Button {
                            selected.removeAll(); sync()
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .help("Clear all attributes")
                    }
                    .padding(8)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Presets").font(.callout).bold()
                    if savedPresets.isEmpty {
                        Text("Save the current attribute combo as a preset for one-click recall.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(savedPresets) { preset in
                                HStack(spacing: 4) {
                                    Button(action: { apply(preset) }) {
                                        Text(preset.name)
                                            .font(.caption)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(Color.secondary.opacity(0.18), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { delete(preset) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    HStack {
                        TextField("New preset name", text: $newPresetName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") { savePreset() }
                            .disabled(selected.isEmpty || newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(8)
        }
        .onAppear {
            // Hydrate from existing instruct text.
            let cur = settings.instruct
            selected = Set(cur.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
            loadPresets()
        }
    }

    private var joined: String {
        selected.sorted().joined(separator: ", ")
    }

    private func toggle(_ value: String) {
        if !selected.insert(value).inserted {
            selected.remove(value)
        }
        sync()
    }

    private func sync() {
        settings.instruct = joined
    }

    private func apply(_ preset: Preset) {
        selected = Set(preset.value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        sync()
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !selected.isEmpty else { return }
        savedPresets.append(.init(id: UUID(), name: name, value: joined))
        newPresetName = ""
        persistPresets()
    }

    private func delete(_ preset: Preset) {
        savedPresets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func loadPresets() {
        guard let data = presetsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        savedPresets = decoded
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(savedPresets),
           let s = String(data: data, encoding: .utf8) {
            presetsRaw = s
        }
    }
}

/// Tiny flow-layout that wraps chips to new lines once they overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var totalW: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
            totalW = max(totalW, x)
        }
        return CGSize(width: totalW, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxW {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
