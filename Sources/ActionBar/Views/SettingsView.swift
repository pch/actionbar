import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @State private var searchText = ""
    @State private var showSelectAllWarning = false

    /// Selecting more repos than this at once asks for confirmation, since each one costs an API call per refresh.
    private static let selectAllWarningThreshold = 10

    private static let intervalOptions: [(label: String, value: TimeInterval)] = [
        ("15s", 15),
        ("30s", 30),
        ("1 min", 60),
        ("5 min", 300),
    ]

    /// What the Reset button restores.
    private var repoSelectionAtOpen: Set<String> {
        appState.runQueryAtSettingsOpen?.repoNames ?? settings.selectedRepoNames
    }

    private var filteredRepos: [Repository] {
        if searchText.isEmpty {
            return appState.availableRepos
        }
        return appState.availableRepos.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pollingIntervalSection
            Divider()
            maxRunsSection
            Divider()
            otherUsersSection
            Divider()
            workflowFilterSection
            Divider()
            installationsSection
            Divider()
            repositoriesHeader
            Divider()
            repositoryList
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.headline)
            Spacer()
            Button("Done") {
                appState.closeSettings()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var pollingIntervalSection: some View {
        HStack {
            Text("Polling interval")
                .font(.subheadline)
            Spacer()
            Picker("Polling interval", selection: Binding(
                get: { settings.pollingInterval },
                set: { appState.updatePollingInterval($0) }
            )) {
                ForEach(Self.intervalOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .settingsSectionPadding()
    }

    private var maxRunsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Max runs per repo")
                    .font(.subheadline)
                Spacer()
                Picker("Max runs per repo", selection: $settings.maxRunsPerRepo) {
                    ForEach(1...10, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Text("Limit how many recent runs are shown for each repository.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .settingsSectionPadding()
    }

    private var otherUsersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Include runs from other users", isOn: $settings.includeRunsFromOtherUsers)
                .toggleStyle(.checkbox)
                .font(.subheadline)
            Text("Show recent workflow runs from anyone in the selected repositories.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSectionPadding()
    }

    private var workflowFilterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workflow filter")
                    .font(.subheadline)
                Spacer()
                Picker("Workflow filter", selection: $settings.workflowFilterMode) {
                    ForEach(WorkflowFilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }

            if settings.workflowFilterMode != .off {
                TextField("e.g. deploy, CI, build", text: $settings.workflowFilterText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 1) {
                    Text(settings.workflowFilterMode == .include
                         ? "Only show workflows matching these names."
                         : "Hide workflows matching these names.")
                    Text("Comma-separated, case-insensitive substring match.")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .settingsSectionPadding()
    }

    private var installationsSection: some View {
        HStack {
            Text("GitHub App")
                .font(.subheadline)
            Spacer()
            Button("Manage installations") {
                openURL(GitHubApp.installationURL)
            }
            .textButtonStyle(.accentColor)
        }
        .settingsSectionPadding()
    }

    private var repositoriesHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Repositories")
                    .font(.subheadline)
                Spacer()
                Button("Refresh repository list", systemImage: "arrow.clockwise") {
                    appState.fetchAvailableRepos(force: true)
                }
                .labelStyle(.iconOnly)
                .textButtonStyle(.accentColor)
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
                Text("\(settings.selectedRepoNames.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("All") {
                    if filteredRepos.count > Self.selectAllWarningThreshold {
                        showSelectAllWarning = true
                    } else {
                        settings.selectAllRepos(filteredRepos.map(\.fullName))
                    }
                }
                .textButtonStyle(.accentColor)
                Button("None") {
                    showSelectAllWarning = false
                    settings.deselectAllRepos()
                }
                .textButtonStyle(.accentColor)
                Button("Reset") {
                    showSelectAllWarning = false
                    settings.selectedRepoNames = repoSelectionAtOpen
                }
                .textButtonStyle(.accentColor)
                .disabled(settings.selectedRepoNames == repoSelectionAtOpen)
            }

            if appState.repoListIsCapped {
                Text("Only the first \(GitHubAPIClient.maxRepositories) repositories are shown.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = appState.repoListError {
                Text("Couldn't load repositories: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showSelectAllWarning {
                selectAllWarning
            }
        }
        .settingsSectionPadding()
    }

    private var selectAllWarning: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Each selected repo requires a separate API call on every refresh. Selecting many repos will slow things down.")
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Select All Anyway") {
                        settings.selectAllRepos(filteredRepos.map(\.fullName))
                        showSelectAllWarning = false
                    }
                    .textButtonStyle(.accentColor, font: .caption2.bold())
                    Button("Cancel") {
                        showSelectAllWarning = false
                    }
                    .textButtonStyle(font: .caption2)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.1)))
    }

    private var repositoryList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredRepos) { repo in
                    repositoryRow(repo, isSelected: settings.selectedRepoNames.contains(repo.fullName))
                }
            }
        }
        .frame(maxHeight: 250)
        .clipped()
    }

    private func repositoryRow(_ repo: Repository, isSelected: Bool) -> some View {
        Button {
            settings.toggleRepo(repo.fullName)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func settingsSectionPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

#Preview {
    let state = AppState()
    state.isAuthenticated = true
    state.availableRepos = [
        Repository(id: 1, fullName: "owner/first-repo"),
        Repository(id: 2, fullName: "owner/second-repo"),
        Repository(id: 3, fullName: "owner/third-repo"),
    ]
    state.settings.selectedRepoNames = ["owner/first-repo", "owner/third-repo"]
    return SettingsView(settings: state.settings)
        .environment(state)
}
