import SwiftUI
import Sparkle

@main
struct TinySpectrumApp: App {
    @StateObject private var model = AppModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).frame(minWidth: 820, minHeight: 680) }
            .windowStyle(.titleBar)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") {
                        updaterController.checkForUpdates(nil)
                    }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                }
            }
    }
}
