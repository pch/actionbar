import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    var isAuthenticated = KeychainService.loadToken() != nil
    var runs: [WorkflowRun] = []
    var isLoading = false
    var errorMessage: String?
    var username: String?
    var deviceCode: DeviceCodeResponse?
    var isLoggingIn = false
    var availableRepos: [Repository] = []
    var isLoadingRepos = false
    var repoListIsCapped = false
    var showingSettings = false
    var needsInstallation = false
    var isCheckingInstallation = false
    private(set) var overallStatus: RunStatus = .unknown

    let settings: SettingsStore

    private let apiClient = GitHubAPIClient()
    private let oauthService = OAuthService()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var installCheckTask: Task<Void, Never>?
    @ObservationIgnored private var oauthTask: Task<Void, Never>?
    @ObservationIgnored private var previousRunStatuses: [Int: String] = [:] // run.id -> run.status
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var isFetchingRuns = false

    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? SettingsStore()
    }

    func start() {
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
        availableRepos = []
        repoListIsCapped = false
        showingSettings = false
        settings.resetAccountSettings()
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
        settings.pollingInterval = interval
        startPolling()
    }

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            await fetchRuns()
            while !Task.isCancelled {
                // Wait in short steps against a wall-clock deadline, so a refresh happens
                // promptly after the Mac wakes from sleep.
                let deadline = Date().addingTimeInterval(settings.pollingInterval)
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
            let usingFallback = !settings.hasRepoConfiguration || settings.selectedRepoNames.isEmpty
            let repos = usingFallback ? nil : Array(settings.selectedRepoNames)
            let actor = settings.includeRunsFromOtherUsers ? nil : username
            let newRuns = try await apiClient.fetchRecentRuns(token: token, actor: actor, repos: repos)

            // With nothing selected yet, adopt the repos that have recent runs as the selection.
            if usingFallback && !newRuns.isEmpty {
                settings.selectedRepoNames = Set(newRuns.map(\.repositoryFullName))
                settings.saveSelectedRepos()
            }

            let workflowFilteredRuns = newRuns.filtered(by: settings.workflowFilterMode, patterns: settings.workflowFilterText)
            let visibleRuns = workflowFilteredRuns.limited(toRunsPerRepo: settings.maxRunsPerRepo)

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

    // MARK: - Repositories

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
