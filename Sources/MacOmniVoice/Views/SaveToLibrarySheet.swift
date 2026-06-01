import SwiftUI

/// Sheet that imports a currently-selected audio file into the
/// reference library, prompting for a name + optional description.
struct SaveToLibrarySheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let source: URL?
    let initialRefText: String
    var onSaved: (ReferenceClip) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var referenceText: String = ""
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save reference clip")
                .font(.title2).bold()

            if let source {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(.tint)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.lastPathComponent).font(.callout)
                        Text(source.deletingLastPathComponent().path)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.callout).bold()
                TextField("e.g. Narrator male calm", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description (optional)").font(.callout).bold()
                TextField("Anything that helps you find it later", text: $description, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript (optional)").font(.callout).bold()
                TextField("Whisper auto-transcribes if blank", text: $referenceText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    save()
                } label: {
                    Text("Save").padding(.horizontal, 8)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(source == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            referenceText = initialRefText
            // Suggest a name from the file
            if let source {
                name = source.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func save() {
        guard let source else { return }
        do {
            let clip = try app.referenceLibrary.importFile(
                from: source,
                name: name,
                description: description,
                referenceText: referenceText
            )
            onSaved(clip)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
