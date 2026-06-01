import SwiftUI
import AppKit

struct ModelStatusBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        // Bridge to a sub-view that explicitly observes ModelManager and
        // SynthesisEngine so their @Published changes drive re-renders.
        ModelStatusBarBody(mm: app.modelManager, engine: app.synthesisEngine)
    }
}

private struct ModelStatusBarBody: View {
    @ObservedObject var mm: ModelManager
    @ObservedObject var engine: SynthesisEngine

    var body: some View {
        VStack(spacing: 8) {
            statusRow
            if let progress = engine.downloadProgress {
                progressRow(progress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }

    private func progressRow(_ p: SynthesisEngine.DownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if p.total > 0 {
                ProgressView(value: p.fraction)
                    .progressViewStyle(.linear)
                Text(p.humanLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(p.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon(for: mm.updateState))
                .imageScale(.large)
                .foregroundStyle(color(for: mm.updateState))

            VStack(alignment: .leading, spacing: 2) {
                Text(headline(for: mm.updateState))
                    .font(.callout).bold()
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            if mm.isChecking {
                ProgressView().controlSize(.small)
            }

            Button {
                revealInFinder()
            } label: {
                Label("Finder", systemImage: "folder")
            }
            .controlSize(.small)
            .help("Reveal the model folder in Finder")

            if case .behind = mm.updateState {
                Button {
                    Task { try? await engine.downloadOrUpdateModel(modelId: mm.modelId) }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if case .notInstalled = mm.updateState {
                Button {
                    Task { try? await engine.downloadOrUpdateModel(modelId: mm.modelId) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button {
                    Task { await mm.checkForUpdate(force: true) }
                } label: {
                    Label("Check", systemImage: "arrow.triangle.2.circlepath")
                }
                .controlSize(.small)
            }
        }
    }

    private func revealInFinder() {
        guard let url = mm.revealableLocation() else { return }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue {
            NSWorkspace.shared.open(url)
        } else if exists {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(PythonRuntime.appSupportDir)
        }
    }

    private func icon(for state: ModelManager.UpdateState) -> String {
        switch state {
        case .upToDate: return "checkmark.seal.fill"
        case .behind:   return "exclamationmark.arrow.triangle.2.circlepath"
        case .notInstalled: return "icloud.and.arrow.down"
        case .error:    return "wifi.exclamationmark"
        case .unknown:  return "questionmark.circle"
        }
    }
    private func color(for state: ModelManager.UpdateState) -> Color {
        switch state {
        case .upToDate: return .green
        case .behind:   return .orange
        case .notInstalled: return .blue
        case .error:    return .red
        case .unknown:  return .gray
        }
    }
    private func headline(for state: ModelManager.UpdateState) -> String {
        switch state {
        case .upToDate(let rev):
            return "Model up to date · \(String(rev.prefix(8)))"
        case .behind(let local, let remote):
            return "Update available · \(String(local.prefix(8))) → \(String(remote.prefix(8)))"
        case .notInstalled:
            return "Model not downloaded yet"
        case .error(let msg):
            return "Update check failed: \(msg)"
        case .unknown:
            return "Checking model status…"
        }
    }
    private var subline: String {
        var parts: [String] = [mm.modelId]

        let downloaded = mm.local?.sizeOnDisk ?? 0
        let total = mm.remote?.totalBytes ?? 0

        if total > 0 && downloaded > 0 {
            parts.append("\(format(downloaded)) / \(format(total)) downloaded")
        } else if total > 0 {
            parts.append("\(format(total)) total")
        } else if downloaded > 0 {
            parts.append("\(format(downloaded)) on disk")
        }

        if let remote = mm.remote, remote.mainFileBytes > 0 {
            parts.append("\(remote.mainFileName.isEmpty ? "main" : remote.mainFileName): \(format(remote.mainFileBytes))")
        }

        return parts.joined(separator: " · ")
    }

    private func format(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 0.95 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }
}
