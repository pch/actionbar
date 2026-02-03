import SwiftUI

@main
struct ActionBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
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
            ? GitHubIcon.statusColor(for: appState.overallStatus)
            : nil
        return GitHubIcon.makeMenuBarIcon(statusDotColor: dotColor)
    }
}
