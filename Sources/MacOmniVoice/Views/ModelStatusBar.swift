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
            .help(finderTooltip)

            Button {
                Task { await mm.checkForUpdate(force: true) }
            } label: {
                Label("Check", systemImage: "arrow.triangle.2.circlepath")
            }
            .controlSize(.small)
            .help("Re-check the HuggingFace Hub for updates")

            Button {
                Task { try? await engine.downloadOrUpdateModel(modelId: mm.modelId) }
            } label: {
                Label(downloadButtonLabel, systemImage: downloadButtonIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(engine.downloadProgress != nil)
            .help(downloadTooltip)
        }
    }

    private var downloadButtonLabel: String {
        if engine.downloadProgress != nil { return "Downloading…" }
        switch mm.updateState {
        case .behind: return "Update"
        case .notInstalled: return "Download"
        default:
            return mm.isFullyDownloaded ? "Re-download" : "Resume download"
        }
    }
    private var downloadButtonIcon: String {
        switch mm.updateState {
        case .behind: return "arrow.down.circle.fill"
        default:
            return mm.isFullyDownloaded ? "arrow.clockwise.circle" : "arrow.down.circle.fill"
        }
    }
    private var downloadTooltip: String {
        switch mm.updateState {
        case .behind: return "Download the newer revision from HuggingFace"
        case .notInstalled: return "Download the model from HuggingFace (~3 GB)"
        default:
            if mm.isFullyDownloaded {
                return "Re-download the model from HuggingFace (verifies file integrity)"
            }
            return "Resume the partial download from HuggingFace"
        }
    }

    private func revealInFinder() {
        guard let url = mm.revealableLocation() else { return }
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists, isDir.boolValue {
            NSWorkspace.shared.open(url)
        } else if exists {
            // For a file (e.g. model.safetensors symlink), use the
            // activateFileViewerSelecting variant so Finder opens the
            // parent folder with the file highlighted.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(PythonRuntime.appSupportDir)
        }
    }

    private var finderTooltip: String {
        guard let url = mm.revealableLocation() else { return "Reveal model in Finder" }
        return "Reveal in Finder: \(url.path)"
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
            if let total = mm.remote?.totalBytes, total > 0,
               let local = mm.local, !mm.isFullyDownloaded {
                let pct = Int((Double(local.sizeOnDisk) / Double(total)) * 100)
                return "Partial download · \(pct)% of \(String(rev.prefix(8)))"
            }
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
