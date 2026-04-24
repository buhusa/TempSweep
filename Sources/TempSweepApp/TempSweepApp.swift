import SwiftUI

@main
struct TempSweepApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About TempSweep") {
                    AboutPanelPresenter.show()
                }
            }
        }
    }
}
