import SwiftUI

@main
struct ActionBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var updater = UpdaterService()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(appState: appState)
                .onAppear { appState.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(nsImage: MenuBarIcon.image(statusDotColor: statusDotColor))
    }

    private var statusDotColor: NSColor? {
        guard appState.isAuthenticated && !appState.runs.isEmpty else { return nil }
        return appState.overallStatus.color
    }
}
