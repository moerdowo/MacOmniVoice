import SwiftUI

struct ModelStatusBar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let mm = app.modelManager
        return HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon(for: mm.updateState))
                .imageScale(.large)
                .foregroundStyle(color(for: mm.updateState))

            VStack(alignment: .leading, spacing: 2) {
                Text(headline(for: mm.updateState))
                    .font(.callout).bold()
                Text(subline(mm: mm))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            if mm.isChecking {
                ProgressView().controlSize(.small)
            }

            if case .behind = mm.updateState {
                Button {
                    Task { try? await app.synthesisEngine.downloadOrUpdateModel(modelId: mm.modelId) }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if case .notInstalled = mm.updateState {
                Button {
                    Task { try? await app.synthesisEngine.downloadOrUpdateModel(modelId: mm.modelId) }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
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
    private func subline(mm: ModelManager) -> String {
        if let local = mm.local {
            let mb = Double(local.sizeOnDisk) / (1024 * 1024)
            return "\(mm.modelId) · \(String(format: "%.0f", mb)) MB · \(local.snapshotPath)"
        }
        return mm.modelId
    }
}
