import SwiftUI

@main
struct MacOmniVoiceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("OmniVoice") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 880, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Model Update…") {
                    Task { await appState.modelManager.checkForUpdate(force: true) }
                }
                .keyboardShortcut("U", modifiers: [.command])
            }
        }
    }
}
