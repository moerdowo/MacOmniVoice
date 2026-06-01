import SwiftUI

struct ConsolePanel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Runner log", systemImage: "terminal").font(.headline)
                Spacer()
                Button {
                    app.synthesisEngine.consoleLog.removeAll()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(app.synthesisEngine.consoleLog.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(10)
                }
                .background(.black.opacity(0.05))
                .onChange(of: app.synthesisEngine.consoleLog.count) { _, n in
                    if n > 0 { withAnimation { proxy.scrollTo(n - 1, anchor: .bottom) } }
                }
            }
        }
        .background(.background)
    }
}
