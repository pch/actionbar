import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let defaultPollingInterval: TimeInterval = 30
    static let defaultMaxRunsPerRepo = 5

    @Published var isAuthenticated = KeychainService.loadToken() != nil
    @Published var runs: [WorkflowRun] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var username: String?
    @Published var deviceCode: DeviceCodeResponse?
    @Published var isLoggingIn = false
    @Published var selectedRepoNames: Set<String> = []
    @Published var repoSelectionSnapshot: Set<String> = []
    @Published var availableRepos: [Repository] = []
    @Published var isLoadingRepos = false
    @Published var repoListIsCapped = false
    @Published var showingSettings = false
    @Published var needsInstallation = false
    @Published var isCheckingInstallation = false
    @Published var pollingInterval = AppState.defaultPollingInterval
    @Published var workflowFilterMode: WorkflowFilterMode = .off
    @Published var workflowFilterText = ""
    @Published var maxRunsPerRepo = AppState.defaultMaxRunsPerRepo
    @Published var includeRunsFromOtherUsers = false
    @Published private(set) var overallStatus: RunStatus = .unknown

    private let apiClient = GitHubAPIClient()
    private let oauthService = OAuthService()
    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?
    private var installCheckTask: Task<Void, Never>?
    private var oauthTask: Task<Void, Never>?
    private var previousRunStatuses: [Int: String] = [:] // run.id -> run.status
    private var hasLoadedOnce = false
    private var isFetchingRuns = false

    private enum DefaultsKey {
        static let selectedRepos = "selectedRepositories"
        static let pollingInterval = "pollingInterval"
        static let workflowFilterMode = "workflowFilterMode"
        static let workflowFilterText = "workflowFilterText"
        static let maxRunsPerRepo = "maxRunsPerRepo"
        static let includeRunsFromOtherUsers = "includeRunsFromOtherUsers"
    }

    private var hasRepoConfiguration: Bool {
        defaults.object(forKey: DefaultsKey.selectedRepos) != nil
    }

    func start() {
        loadSettings()
        guard let token = KeychainService.loadToken() else { return }
        isAuthenticated = true
        Task {
            if let user = try? await apiClient.validateToken(token) {
                username = user.login
            }
            await startMonitoring(token: token)
        }
    }

    // MARK: - Authentication

    func loginWithGitHub() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        errorMessage = nil
        deviceCode = nil

        oauthTask = Task {
            do {
                let codeResponse = try await oauthService.requestDeviceCode()
                deviceCode = codeResponse

                if let url = URL(string: codeResponse.verificationUri) {
                    NSWorkspace.shared.open(url)
                }

                let token = try await oauthService.pollForToken(
                    deviceCode: codeResponse.deviceCode,
                    interval: codeResponse.interval
                )

                let user = try await apiClient.validateToken(token)
                try KeychainService.saveToken(token)

                username = user.login
                isAuthenticated = true
                deviceCode = nil
                isLoggingIn = false

                await startMonitoring(token: token)
            } catch {
                if !(error is CancellationError) {
                    errorMessage = error.localizedDescription
                }
                deviceCode = nil
                isLoggingIn = false
            }
        }
    }

    func cancelLogin() {
        oauthTask?.cancel()
        oauthTask = nil
        deviceCode = nil
        isLoggingIn = false
        errorMessage = nil
    }

    func signOut() {
        cancelLogin()
        stopPolling()
        stopInstallCheckTimer()
        Task {
            await apiClient.clearConditionalCache()
        }
        KeychainService.deleteToken()
        isAuthenticated = false
        needsInstallation = false
        overallStatus = .unknown
        runs = []
        username = nil
        previousRunStatuses = [:]
        hasLoadedOnce = false
        errorMessage = nil
        selectedRepoNames = []
        availableRepos = []
        repoListIsCapped = false
        showingSettings = false
        workflowFilterMode = .off
        workflowFilterText = ""
        maxRunsPerRepo = Self.defaultMaxRunsPerRepo
        includeRunsFromOtherUsers = false
        // The polling interval is a device preference, so it survives signing out.
        for key in [
            DefaultsKey.selectedRepos,
            DefaultsKey.workflowFilterMode,
            DefaultsKey.workflowFilterText,
            DefaultsKey.maxRunsPerRepo,
            DefaultsKey.includeRunsFromOtherUsers,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - GitHub App Installation

    /// Starts polling if the GitHub App is installed, otherwise waits for it to be installed.
    private func startMonitoring(token: String) async {
        do {
            if try await apiClient.hasInstallations(token: token) {
                startPolling()
            } else {
                needsInstallation = true
                startInstallCheckTimer()
            }
        } catch {
            // Don't assume there are no installations; fetchRuns will surface real errors.
            startPolling()
        }
    }

    func checkInstallationAndStart() {
        guard let token = KeychainService.loadToken() else { return }
        isCheckingInstallation = true
        Task {
            do {
                if try await apiClient.hasInstallations(token: token) {
                    installationFound()
                } else {
                    errorMessage = "No installation found yet. Please install the app on GitHub first. If you did, wait a bit."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isCheckingInstallation = false
        }
    }

    private func startInstallCheckTimer() {
        stopInstallCheckTimer()
        installCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                guard let token = KeychainService.loadToken() else { continue }
                if (try? await apiClient.hasInstallations(token: token)) == true {
                    installationFound()
                    break
                }
            }
        }
    }

    private func stopInstallCheckTimer() {
        installCheckTask?.cancel()
        installCheckTask = nil
    }

    private func installationFound() {
        stopInstallCheckTimer()
        needsInstallation = false
        errorMessage = nil
        startPolling()
    }

    // MARK: - Polling

    func refreshNow() {
        isLoading = true
        Task {
            let start = ContinuousClock.now
            await fetchRuns(manageLoading: false)
            // Keep the spinner up long enough to register as feedback.
            try? await Task.sleep(until: start + .milliseconds(500), clock: .continuous)
            isLoading = false
        }
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        pollingInterval = interval
        defaults.set(pollingInterval, forKey: DefaultsKey.pollingInterval)
        startPolling()
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            await fetchRuns()
            while !Task.isCancelled {
                // Wait in short steps against a wall-clock deadline, so a refresh happens
                // promptly after the Mac wakes from sleep.
                let deadline = Date().addingTimeInterval(pollingInterval)
                while Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { break }
                await fetchRuns()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func fetchRuns(manageLoading: Bool = true) async {
        guard !isFetchingRuns else { return }
        isFetchingRuns = true
        defer { isFetchingRuns = false }

        guard let token = KeychainService.loadToken() else {
            isAuthenticated = false
            return
        }

        if manageLoading && !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil

        do {
            let usingFallback = !hasRepoConfiguration || selectedRepoNames.isEmpty
            let repos = usingFallback ? nil : Array(selectedRepoNames)
            let actor = includeRunsFromOtherUsers ? nil : username
            let newRuns = try await apiClient.fetchRecentRuns(token: token, actor: actor, repos: repos)

            // With nothing selected yet, adopt the repos that have recent runs as the selection.
            if usingFallback && !newRuns.isEmpty {
                selectedRepoNames = Set(newRuns.map(\.repositoryFullName))
                saveSelectedRepos()
            }

            let workflowFilteredRuns = newRuns.filtered(by: workflowFilterMode, patterns: workflowFilterText)
            let visibleRuns = workflowFilteredRuns.limited(toRunsPerRepo: maxRunsPerRepo)

            if hasLoadedOnce {
                notifyCompletedRuns(in: visibleRuns)
            }
            previousRunStatuses = [:]
            for run in visibleRuns {
                previousRunStatuses[run.id] = run.status
            }

            overallStatus = workflowFilteredRuns.overallStatus
            runs = visibleRuns
            hasLoadedOnce = true
        } catch GitHubAPIError.invalidToken {
            signOut()
        } catch is CancellationError {
            // Task was cancelled (e.g. polling restart) — don't surface to UI.
        } catch {
            errorMessage = error.localizedDescription
        }

        if manageLoading { isLoading = false }
    }

    /// Notifies about runs that were queued or in progress on the previous fetch and have now completed.
    private func notifyCompletedRuns(in newRuns: [WorkflowRun]) {
        for run in newRuns where run.status == "completed" {
            if let previousStatus = previousRunStatuses[run.id], ["in_progress", "queued"].contains(previousStatus) {
                NotificationService.sendCompletionNotification(run: run)
            }
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        if let saved = defaults.stringArray(forKey: DefaultsKey.selectedRepos) {
            selectedRepoNames = Set(saved)
        }

        let savedInterval = defaults.double(forKey: DefaultsKey.pollingInterval)
        pollingInterval = savedInterval > 0 ? savedInterval : Self.defaultPollingInterval

        if let modeRaw = defaults.string(forKey: DefaultsKey.workflowFilterMode),
           let mode = WorkflowFilterMode(rawValue: modeRaw) {
            workflowFilterMode = mode
        }
        workflowFilterText = defaults.string(forKey: DefaultsKey.workflowFilterText) ?? ""

        let savedMaxRuns = defaults.integer(forKey: DefaultsKey.maxRunsPerRepo)
        maxRunsPerRepo = savedMaxRuns > 0 ? savedMaxRuns : Self.defaultMaxRunsPerRepo

        includeRunsFromOtherUsers = defaults.bool(forKey: DefaultsKey.includeRunsFromOtherUsers)
    }

    /// Persists the settings edited in the settings panel. The polling interval is saved as soon as it changes.
    func saveSettings() {
        saveSelectedRepos()
        defaults.set(workflowFilterMode.rawValue, forKey: DefaultsKey.workflowFilterMode)
        defaults.set(workflowFilterText, forKey: DefaultsKey.workflowFilterText)
        defaults.set(maxRunsPerRepo, forKey: DefaultsKey.maxRunsPerRepo)
        defaults.set(includeRunsFromOtherUsers, forKey: DefaultsKey.includeRunsFromOtherUsers)
    }

    private func saveSelectedRepos() {
        defaults.set(Array(selectedRepoNames), forKey: DefaultsKey.selectedRepos)
    }

    // MARK: - Repository Selection

    func snapshotSelectedRepos() {
        repoSelectionSnapshot = Set(defaults.stringArray(forKey: DefaultsKey.selectedRepos) ?? [])
    }

    func resetReposToSnapshot() {
        selectedRepoNames = repoSelectionSnapshot
    }

    func toggleRepo(_ repoName: String) {
        if selectedRepoNames.contains(repoName) {
            selectedRepoNames.remove(repoName)
        } else {
            selectedRepoNames.insert(repoName)
        }
    }

    func selectAllRepos(_ repoNames: [String]) {
        selectedRepoNames = Set(repoNames)
    }

    func deselectAllRepos() {
        selectedRepoNames = []
    }

    func fetchAvailableRepos(force: Bool = false) {
        guard let token = KeychainService.loadToken() else { return }
        if !force && !availableRepos.isEmpty { return }
        isLoadingRepos = true
        Task {
            // On failure, keep whatever list we had before.
            if let repos = try? await apiClient.fetchAllRepos(token: token) {
                availableRepos = repos
                repoListIsCapped = repos.count >= GitHubAPIClient.maxRepositories
            }
            isLoadingRepos = false
        }
    }
}
