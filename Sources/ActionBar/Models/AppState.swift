import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    var isAuthenticated = KeychainService.loadToken() != nil
    var runs: [WorkflowRun] = []
    /// Repositories whose runs failed to load on the last fetch, while others loaded fine.
    var failedRepos: [String] = []
    var isLoading = false
    var errorMessage: String?
    var username: String?
    var deviceCode: DeviceCodeResponse?
    var isLoggingIn = false
    var availableRepos: [Repository] = []
    var isLoadingRepos = false
    var repoListIsCapped = false
    var repoListError: String?
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
    @ObservationIgnored private var previousRunStatuses: [Int: RunStatus] = [:] // run.id -> status
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var isFetchingRuns = false

    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? SettingsStore()
    }

    /// Resumes the saved session. Safe to call more than once; only the first call does anything.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
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
        failedRepos = []
        username = nil
        previousRunStatuses = [:]
        hasLoadedOnce = false
        errorMessage = nil
        availableRepos = []
        repoListIsCapped = false
        repoListError = nil
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
            let usingFallback = settings.selectedRepoNames.isEmpty
            let repos = usingFallback ? nil : Array(settings.selectedRepoNames)
            let actor = settings.includeRunsFromOtherUsers ? nil : username
            let recentRuns = try await apiClient.fetchRecentRuns(token: token, actor: actor, repos: repos)
            let newRuns = recentRuns.runs

            // With nothing selected yet, adopt the repos that have recent runs as the selection.
            if usingFallback && !newRuns.isEmpty {
                settings.selectedRepoNames = Set(newRuns.map(\.repositoryFullName))
            }

            let workflowFilteredRuns = newRuns.filtered(by: settings.workflowFilterMode, patterns: settings.workflowFilterText)
            let visibleRuns = workflowFilteredRuns.limited(toRunsPerRepo: settings.maxRunsPerRepo)

            if hasLoadedOnce {
                for run in visibleRuns.newlyCompleted(since: previousRunStatuses) {
                    NotificationService.sendCompletionNotification(run: run)
                }
            }
            previousRunStatuses = [:]
            for run in visibleRuns {
                previousRunStatuses[run.id] = RunStatus(from: run)
            }

            overallStatus = workflowFilteredRuns.overallStatus
            runs = visibleRuns
            failedRepos = recentRuns.failedRepos
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

    // MARK: - Repositories

    func fetchAvailableRepos(force: Bool = false) {
        guard let token = KeychainService.loadToken() else { return }
        if !force && !availableRepos.isEmpty { return }
        isLoadingRepos = true
        repoListError = nil
        Task {
            do {
                let repos = try await apiClient.fetchAllRepos(token: token)
                availableRepos = repos
                repoListIsCapped = repos.count >= GitHubAPIClient.maxRepositories
            } catch {
                // Keep whatever list we had before.
                repoListError = error.localizedDescription
            }
            isLoadingRepos = false
        }
    }
}
