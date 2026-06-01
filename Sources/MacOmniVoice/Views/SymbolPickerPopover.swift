import SwiftUI

/// Popover that inserts an OmniVoice non-verbal symbol at the user's
/// caret. The caret position isn't reachable in pure SwiftUI's
/// TextEditor, so we append to the current text and let the user
/// move it if needed — fast enough and good enough.
struct SymbolPickerPopover: View {
    @Binding var text: String

    static let symbols: [(group: String, items: [(label: String, token: String)])] = [
        ("Common", [
            ("laughter",        "[laughter]"),
            ("sigh",            "[sigh]"),
        ]),
        ("English confirmation / question", [
            ("confirmation",    "[confirmation-en]"),
            ("question",        "[question-en]"),
            ("question ah",     "[question-ah]"),
            ("question oh",     "[question-oh]"),
            ("question ei",     "[question-ei]"),
            ("question yi",     "[question-yi]"),
        ]),
        ("Surprise / dissatisfaction", [
            ("surprise ah",     "[surprise-ah]"),
            ("surprise oh",     "[surprise-oh]"),
            ("surprise wa",     "[surprise-wa]"),
            ("surprise yo",     "[surprise-yo]"),
            ("dissatisfaction", "[dissatisfaction-hnn]"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insert non-verbal symbol").font(.headline)
            ForEach(Self.symbols, id: \.group) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.group).font(.caption).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(section.items, id: \.token) { item in
                            Button {
                                insert(item.token)
                            } label: {
                                Text(item.label)
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                            .help(item.token)
                        }
                    }
                }
            }
            Divider()
            Text("Tags are appended to the end of the text. Move them where you need.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 360)
    }

    private func insert(_ token: String) {
        let needsSpace = !text.isEmpty && !text.hasSuffix(" ") && !text.hasSuffix("\n")
        text += (needsSpace ? " " : "") + token + " "
    }
}
