import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            switch app.currentStage {
            case .checking:
                LoadingScreen(message: "Checking environment…")
            case .needsSetup, .settingUp:
                SetupView()
            case .ready:
                MainView()
            }
        }
        .background(.background)
    }
}

struct LoadingScreen: View {
    let message: String
    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
