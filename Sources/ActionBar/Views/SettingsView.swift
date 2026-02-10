import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var showSelectAllWarning = false

    private let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("15s", 15),
        ("30s", 30),
        ("1 min", 60),
        ("5 min", 300),
    ]

    private var filteredRepos: [Repository] {
        if searchText.isEmpty {
            return appState.availableRepos
        }
        return appState.availableRepos.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedCount: Int {
        appState.selectedRepoNames.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    appState.saveSelectedRepos()
                    appState.saveWorkflowFilter()
                    appState.showingSettings = false
                    appState.refreshNow()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Polling interval
            HStack {
                Text("Polling interval")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: Binding(
                    get: { appState.pollingInterval },
                    set: { appState.updatePollingInterval($0) }
                )) {
                    ForEach(intervalOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Workflow filter
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Workflow filter")
                        .font(.subheadline)
                    Spacer()
                    Picker("", selection: $appState.workflowFilterMode) {
                        ForEach(WorkflowFilterMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()
                }

                if appState.workflowFilterMode != .off {
                    TextField("e.g. deploy, CI, build", text: $appState.workflowFilterText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(appState.workflowFilterMode == .include
                             ? "Only show workflows matching these names."
                             : "Hide workflows matching these names.")
                        Text("Comma-separated, case-insensitive substring match.")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // GitHub App installations
            HStack {
                Text("GitHub App")
                    .font(.subheadline)
                Spacer()
                Button("Manage installations") {
                    if let url = URL(string: "https://github.com/apps/actionbar-macos") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Repositories section header
            VStack(spacing: 6) {
                HStack {
                    Text("Repositories")
                        .font(.subheadline)
                    Spacer()
                    Button(action: { appState.fetchAvailableRepos(force: true) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help("Refresh repository list")
                    .opacity(appState.isLoadingRepos ? 0 : 1)
                    .overlay {
                        if appState.isLoadingRepos {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .disabled(appState.isLoadingRepos)
                }

                TextField("Search repos...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                HStack {
                    Text("\(selectedCount) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("All") {
                        if filteredRepos.count > 10 {
                            showSelectAllWarning = true
                        } else {
                            appState.selectAllRepos(filteredRepos.map(\.fullName))
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    Button("None") {
                        showSelectAllWarning = false
                        appState.deselectAllRepos()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    Button("Reset") {
                        showSelectAllWarning = false
                        appState.resetReposToSnapshot()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(appState.selectedRepoNames == appState.repoSelectionSnapshot)
                }

                if appState.repoListIsCapped {
                    Text("Only the first 200 repositories are shown.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showSelectAllWarning {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Each selected repo requires a separate API call on every refresh. Selecting many repos will slow things down.")
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 12) {
                                Button("Select All Anyway") {
                                    appState.selectAllRepos(filteredRepos.map(\.fullName))
                                    showSelectAllWarning = false
                                }
                                .font(.caption2.bold())
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                Button("Cancel") {
                                    showSelectAllWarning = false
                                }
                                .font(.caption2)
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.1)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Repo list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredRepos) { repo in
                        Button(action: { appState.toggleRepo(repo.fullName) }) {
                            HStack(spacing: 8) {
                                Image(systemName: appState.selectedRepoNames.contains(repo.fullName)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(appState.selectedRepoNames.contains(repo.fullName)
                                        ? .accentColor : .secondary)
                                    .font(.system(size: 13))
                                Text(repo.fullName)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
        .onAppear {
            appState.snapshotSelectedRepos()
        }
    }
}

#Preview {
    let state = AppState()
    state.isAuthenticated = true
    state.availableRepos = [
        Repository(id: 1, fullName: "owner/first-repo", htmlUrl: "https://github.com/owner/first-repo"),
        Repository(id: 2, fullName: "owner/second-repo", htmlUrl: "https://github.com/owner/second-repo"),
        Repository(id: 3, fullName: "owner/third-repo", htmlUrl: "https://github.com/owner/third-repo"),
    ]
    state.selectedRepoNames = ["owner/first-repo", "owner/third-repo"]
    return SettingsView()
        .environmentObject(state)
}
