import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: URL
    @State private var format: AudioExportFormat = .wav
    @State private var sampleRate: Double = 24_000
    @State private var bitDepth: Int = 16
    @State private var isExporting = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export audio").font(.title2).bold()
            Text("Convert “\(source.lastPathComponent)” to a different format.")
                .font(.callout).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Format").font(.callout).bold()
                Picker("", selection: $format) {
                    ForEach(AudioExportFormat.allCases.filter { $0.supportedNatively }) { f in
                        Text(f.displayName).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if format == .wav || format == .caf || format == .flac {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sample rate").font(.caption).bold()
                        Picker("", selection: $sampleRate) {
                            Text("24 000 Hz (model native)").tag(24_000.0)
                            Text("44 100 Hz").tag(44_100.0)
                            Text("48 000 Hz").tag(48_000.0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bit depth").font(.caption).bold()
                        Picker("", selection: $bitDepth) {
                            Text("16-bit").tag(16)
                            Text("24-bit").tag(24)
                            Text("32-bit").tag(32)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    runExport()
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small).padding(.horizontal, 16)
                    } else {
                        Text("Export…").padding(.horizontal, 8)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func runExport() {
        let panel = NSSavePanel()
        if let ut = UTType(filenameExtension: format.pathExtension) {
            panel.allowedContentTypes = [ut]
        }
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent
            + "." + format.pathExtension
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        isExporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AudioExporter.export(input: source, to: dest,
                                         format: format,
                                         sampleRate: sampleRate,
                                         bitDepth: bitDepth)
                DispatchQueue.main.async {
                    isExporting = false
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                    dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    isExporting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
