import SwiftUI

struct SetupView: View {
    @EnvironmentObject var app: AppState
    @State private var lines: [String] = []
    @State private var isRunning = false
    @State private var failure: String? = nil
    @State private var detectedPython: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    requirementRow(
                        title: "Host Python 3.10+",
                        ok: detectedPython != nil,
                        detail: detectedPython?.path ?? "Not found"
                    )
                    requirementRow(
                        title: "Disk space (≈ 6 GB for PyTorch + model)",
                        ok: true,
                        detail: "App data goes to ~/Library/Application Support/MacOmniVoice"
                    )
                }
                .padding(8)
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 180, maxHeight: 320)
                .background(.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .onChange(of: lines.count) { _, _ in
                    withAnimation { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
                }
            }

            HStack {
                Button {
                    detectedPython = app.pythonRuntime.findHostPython()
                } label: {
                    Label("Re-detect Python", systemImage: "arrow.clockwise")
                }
                .disabled(isRunning)

                Spacer()

                Button {
                    Task { await runSetup() }
                } label: {
                    if isRunning {
                        ProgressView().controlSize(.small).padding(.horizontal, 16)
                    } else {
                        Text("Install OmniVoice")
                            .padding(.horizontal, 18)
                            .padding(.vertical, 4)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRunning || detectedPython == nil)
            }
        }
        .padding(32)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            detectedPython = app.pythonRuntime.findHostPython()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to OmniVoice")
                .font(.largeTitle).bold()
            Text("One-time setup will create a private Python environment for OmniVoice and install PyTorch (~3–5 GB). The model itself downloads from HuggingFace on the first synthesis.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requirementRow(title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func runSetup() async {
        isRunning = true
        failure = nil
        lines.removeAll()
        do {
            try await app.beginSetup { line in
                lines.append(line)
            }
        } catch {
            failure = error.localizedDescription
        }
        isRunning = false
    }
}
