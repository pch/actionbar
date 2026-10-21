import SwiftUI

@main
struct ActionBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Image(nsImage: makeIcon())
    }

    private func makeIcon() -> NSImage {
        let dotColor: NSColor? = appState.isAuthenticated && !appState.runs.isEmpty
            ? MenuBarIcon.statusColor(for: appState.overallStatus)
            : nil
        return MenuBarIcon.makeMenuBarIcon(statusDotColor: dotColor)
    }
}
