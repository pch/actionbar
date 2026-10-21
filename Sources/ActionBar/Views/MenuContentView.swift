import SwiftUI

struct MenuContentView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var updater: UpdaterService
    @State private var now = Date()
    @State private var showAbout = false

    var body: some View {
        if appState.isAuthenticated && !appState.needsInstallation {
            authenticatedView
        } else {
            SetupView()
        }
    }

    private var authenticatedView: some View {
        VStack(spacing: 0) {
            if appState.showingSettings {
                SettingsView(settings: appState.settings)
                    .frame(minHeight: 520)
            } else {
                header
                Divider()
                content
            }

            Divider()

            footer
        }
        .frame(width: 340)
        .task {
            // Keep relative timestamps fresh while the menu is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            now = Date()
        }
    }

    private var header: some View {
        HStack {
            Text("GitHub Actions")
                .font(.headline)
            Spacer()
            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Refresh now", systemImage: "arrow.clockwise") {
                appState.refreshNow()
            }
            .help("Refresh now")
            Button("Settings", systemImage: "gearshape") {
                appState.showingSettings = true
                appState.fetchAvailableRepos()
            }
            .help("Settings")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let error = appState.errorMessage {
            errorView(error)
        } else if appState.runs.isEmpty && appState.isLoading {
            loadingView
        } else if appState.runs.isEmpty {
            emptyView
        } else {
            runsList
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            if let username = appState.username {
                Text(username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("About") {
                showAbout.toggle()
            }
            .textButtonStyle()
            .popover(isPresented: $showAbout) {
                AboutView()
                    .environmentObject(updater)
            }

            Button("Sign Out") {
                appState.signOut()
            }
            .textButtonStyle()

            QuitButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var runsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.runs) { run in
                    WorkflowRowView(
                        run: run,
                        now: now,
                        showsTriggeringActor: appState.settings.includeRunsFromOtherUsers
                    )

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
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
        }
        .padding(30)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 20))
            Text("No workflow runs found")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(30)
    }
}

#Preview("With Runs") {
    let state = AppState()
    state.isAuthenticated = true
    state.username = "octocat"
    state.runs = [
        WorkflowRun(
            id: 1, name: "CI", displayTitle: "Fix login bug",
            status: "completed", conclusion: "success",
            htmlUrl: "https://github.com/owner/repo/actions/runs/1",
            headBranch: "main",
            updatedAt: Date().addingTimeInterval(-300),
            repositoryFullName: "owner/repo"
        ),
        WorkflowRun(
            id: 2, name: "Tests", displayTitle: "Update dependencies",
            status: "completed", conclusion: "failure",
            htmlUrl: "https://github.com/owner/repo/actions/runs/2",
            headBranch: "feature/auth",
            updatedAt: Date().addingTimeInterval(-600),
            repositoryFullName: "owner/other-repo"
        ),
        WorkflowRun(
            id: 3, name: "Deploy", displayTitle: "Deploy to production",
            status: "in_progress", conclusion: nil,
            htmlUrl: "https://github.com/owner/repo/actions/runs/3",
            headBranch: "main",
            updatedAt: Date(),
            repositoryFullName: "owner/repo"
        ),
    ]
    return MenuContentView()
        .environment(state)
        .environmentObject(UpdaterService())
}

#Preview("Empty") {
    let state = AppState()
    state.isAuthenticated = true
    state.username = "octocat"
    return MenuContentView()
        .environment(state)
        .environmentObject(UpdaterService())
}

#Preview("Loading") {
    let state = AppState()
    state.isAuthenticated = true
    state.username = "octocat"
    state.isLoading = true
    return MenuContentView()
        .environment(state)
        .environmentObject(UpdaterService())
}
