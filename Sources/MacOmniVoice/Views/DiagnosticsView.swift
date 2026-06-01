import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    runnerCard
                    integrityCard
                    selfTestCard
                    bundleCard
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 540)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Diagnostics").font(.title2).bold()
                Text("Verify the install, run a self-test, and export a bug-report bundle.")
                    .foregroundStyle(.secondary).font(.callout)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    // MARK: Cards

    private var runnerCard: some View {
        DiagnosticCard(
            title: "Python runner",
            icon: "ladybug",
            iconTint: app.pythonRuntime.isRunnerLive ? .green : .red
        ) {
            HStack(spacing: 14) {
                statBox("Status",   app.pythonRuntime.isRunnerLive ? "alive" : "down")
                statBox("Restarts", "\(app.pythonRuntime.restartCount)")
                statBox("Device",   app.pythonRuntime.detectedDevice ?? "?")
                statBox("Model",    app.synthesisEngine.modelLoaded ? "loaded" : "—")
            }
            if let crash = app.pythonRuntime.lastCrashMessage {
                Text(crash).font(.caption).foregroundStyle(.orange).padding(.top, 4)
            }
            HStack {
                Button {
                    app.pythonRuntime.stopRunner()
                    app.pythonRuntime.autoRestartEnabled = true
                    try? app.pythonRuntime.startRunnerIfNeeded()
                } label: { Label("Restart runner", systemImage: "arrow.clockwise.circle") }
            }
        }
    }

    private var integrityCard: some View {
        DiagnosticCard(
            title: "Model integrity",
            icon: "shield.lefthalf.filled",
            iconTint: app.diagnostics.lastVerification?.ok == true ? .green
                    : app.diagnostics.lastVerification?.ok == false ? .red : .gray
        ) {
            Text("Stream-hashes every cached blob with SHA-256 and compares against the HuggingFace LFS manifest. Catches half-downloaded or corrupted weights.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let p = app.diagnostics.verifyProgress {
                Text(p).font(.caption2).foregroundStyle(.tint)
            }

            if let r = app.diagnostics.lastVerification {
                resultsRow(r)
            }

            HStack {
                Button {
                    Task {
                        _ = try? await app.diagnostics.verifyModel(
                            runtime: app.pythonRuntime,
                            modelId: app.modelManager.modelId)
                    }
                } label: {
                    HStack {
                        if app.diagnostics.isVerifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Verify model")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.diagnostics.isVerifying || !app.modelManager.isFullyDownloaded)

                if !app.modelManager.isFullyDownloaded {
                    Text("Download the model first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultsRow(_ r: DiagnosticsService.VerificationResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                r.ok ? "All files verified OK"
                     : (r.error ?? "Some files failed verification"),
                systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(r.ok ? .green : .red)
            .font(.callout)

            if !r.files.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(r.files, id: \.path) { f in
                            HStack {
                                Image(systemName: statusIcon(f.status))
                                    .foregroundStyle(statusColor(f.status))
                                Text(f.path).font(.caption).monospaced()
                                Spacer()
                                Text(f.status).font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func statusIcon(_ s: String) -> String {
        switch s {
        case "ok": return "checkmark.circle.fill"
        case "missing": return "questionmark.circle"
        default: return "xmark.octagon.fill"
        }
    }
    private func statusColor(_ s: String) -> Color {
        switch s {
        case "ok": return .green
        case "missing": return .gray
        default: return .red
        }
    }

    private var selfTestCard: some View {
        DiagnosticCard(
            title: "Self-test",
            icon: "checkmark.seal",
            iconTint: app.diagnostics.lastSelfTest?.ok == true ? .green
                    : app.diagnostics.lastSelfTest?.ok == false ? .red : .gray
        ) {
            Text("Synthesizes a fixed English sentence with low inference steps to verify the whole stack works end-to-end.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let r = app.diagnostics.lastSelfTest {
                Label(
                    String(format: "%@ — %.1fs", r.message, r.elapsed),
                    systemImage: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(r.ok ? .green : .red)
            }
            HStack {
                Button {
                    Task {
                        _ = await app.diagnostics.runSelfTest(
                            engine: app.synthesisEngine,
                            settings: app.settings)
                    }
                } label: {
                    HStack {
                        if app.diagnostics.isRunningSelfTest {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "play.circle")
                        }
                        Text("Run self-test")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.diagnostics.isRunningSelfTest ||
                          app.preflightForGenerate(text: "OmniVoice is now installed and working on this Mac.") != .ready)
            }
        }
    }

    private var bundleCard: some View {
        DiagnosticCard(
            title: "Debug bundle",
            icon: "doc.zipper",
            iconTint: .blue
        ) {
            Text("Zips system info, engine log, ref-library.json, pip freeze, and the active runner script under ~/Downloads. Drop this on a GitHub issue and we can diagnose far faster.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    _ = app.diagnostics.exportDebugBundle(app: app)
                } label: {
                    HStack {
                        if app.diagnostics.isExportingBundle {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Export bundle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(app.diagnostics.isExportingBundle)
            }
        }
    }

    // MARK: helpers

    private func statBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout).bold().monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct DiagnosticCard<Content: View>: View {
    let title: String
    let icon: String
    let iconTint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon).foregroundStyle(iconTint)
                    Text(title).font(.headline)
                }
                content()
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
