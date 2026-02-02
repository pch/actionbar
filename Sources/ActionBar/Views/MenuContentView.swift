import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var now = Date()
    @State private var showAbout = false

    private let tickTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        if appState.isAuthenticated && !appState.needsInstallation {
            authenticatedView
        } else {
            SetupView()
                .environmentObject(appState)
        }
    }

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("GitHub Actions")
                    .font(.headline)
                Spacer()
                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: { appState.refreshNow() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Refresh now")
                Button(action: {
                    appState.showingSettings = true
                    appState.fetchAvailableRepos()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Content
            if appState.showingSettings {
                SettingsView()
            } else if let error = appState.errorMessage {
                errorView(error)
            } else if appState.runs.isEmpty && appState.isLoading {
                loadingView
            } else if appState.runs.isEmpty {
                emptyView
            } else {
                runsList
            }

            Divider()

            // Footer
            HStack(spacing: 16) {
                if let username = appState.username {
                    Text(username)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("About") {
                    showAbout.toggle()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .popover(isPresented: $showAbout) {
                    AboutView()
                }

                Button("Sign Out") {
                    appState.signOut()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
        .onReceive(tickTimer) { now = $0 }
    }

    private var runsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.runs) { run in
                    WorkflowRowView(run: run, now: now)

                    if run.id != appState.runs.last?.id {
                        Divider()
                            .opacity(0.35)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                appState.refreshNow()
            }
            .font(.caption)
        }
        .padding(20)
    }

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Loading workflows...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            Text("No workflow runs found")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(30)
    }
}
