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
    private(set) var showingSettings = false
    /// The run query from when Settings was opened. Polls keep using it until Settings closes,
    /// so half-finished edits (like an empty selection) don't reach the menu or notifications.
    private(set) var runQueryAtSettingsOpen: SettingsStore.RunQuery?
    var needsInstallation = false
    var isCheckingInstallation = false
    private(set) var overallStatus: RunStatus = .unknown

    let settings: SettingsStore

    private let apiClient = GitHubAPIClient()
    private let oauthService = OAuthService()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var installCheckTask: Task<Void, Never>?
    @ObservationIgnored private var oauthTask: Task<Void, Never>?
    @ObservationIgnored private var runHistory = RunHistory()
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var isFetchingRuns = false
    @ObservationIgnored private var refetchRequested = false
    /// Changes on sign-out, so a fetch that was in flight doesn't apply its results afterwards.
    @ObservationIgnored private var sessionID = 0
    @ObservationIgnored private var repoListTask: Task<Void, Never>?

    init(settings: SettingsStore? = nil) {
        self.settings = settings ?? SettingsStore()
    }

    /// Resumes the saved session. Safe to call more than once; only the first call does anything.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard let token = KeychainService.loadToken() else { return }
        isAuthenticated = true
        let sessionID = self.sessionID
        Task {
            let user = try? await apiClient.validateToken(token)
            guard sessionID == self.sessionID else { return }
            if let user {
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
        repoListTask?.cancel()
        repoListTask = nil
        isLoadingRepos = false
        Task {
            await apiClient.clearConditionalCache()
        }
        KeychainService.deleteToken()
        sessionID += 1
        isAuthenticated = false
        needsInstallation = false
        overallStatus = .unknown
        runs = []
        failedRepos = []
        username = nil
        runHistory = RunHistory()
        hasLoadedOnce = false
        errorMessage = nil
        availableRepos = []
        repoListIsCapped = false
        repoListError = nil
        showingSettings = false
        runQueryAtSettingsOpen = nil
        settings.resetAccountSettings()
    }

    // MARK: - GitHub App Installation

    /// Starts polling if the GitHub App is installed, otherwise waits for it to be installed.
    private func startMonitoring(token: String) async {
        let sessionID = self.sessionID
        let hasInstallations: Bool
        do {
            hasInstallations = try await apiClient.hasInstallations(token: token)
        } catch {
            // Don't assume there are no installations; fetchRuns will surface real errors.
            hasInstallations = true
        }
        guard sessionID == self.sessionID else { return }

        if hasInstallations {
            startPolling()
        } else {
            stopPolling()
            needsInstallation = true
            startInstallCheckTimer()
        }
    }

    func checkInstallationAndStart() {
        guard let token = KeychainService.loadToken() else { return }
        isCheckingInstallation = true
        let sessionID = self.sessionID
        Task {
            defer { isCheckingInstallation = false }
            do {
                let hasInstallations = try await apiClient.hasInstallations(token: token)
                guard sessionID == self.sessionID else { return }
                if hasInstallations {
                    installationFound()
                } else {
                    errorMessage = "No installation found yet. Please install the app on GitHub first. If you did, wait a bit."
                }
            } catch {
                guard sessionID == self.sessionID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startInstallCheckTimer() {
        stopInstallCheckTimer()
        let sessionID = self.sessionID
        installCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                guard let token = KeychainService.loadToken() else { continue }
                let hasInstallations = (try? await apiClient.hasInstallations(token: token)) == true
                guard !Task.isCancelled, sessionID == self.sessionID else { break }
                if hasInstallations {
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

    // MARK: - Settings

    func openSettings() {
        runQueryAtSettingsOpen = settings.runQuery
        showingSettings = true
        fetchAvailableRepos()
    }

    func closeSettings() {
        showingSettings = false
        runQueryAtSettingsOpen = nil
        refreshNow()
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
        let previousPollTask = pollTask
        stopPolling()
        pollTask = Task {
            // Let a cancelled poll wind down first. Otherwise its fetch would still be in flight,
            // this fetch would be skipped, and nothing would refresh until the next interval.
            await previousPollTask?.value
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
        guard !isFetchingRuns else {
            // Fetch again once the current fetch finishes, so this refresh isn't lost.
            refetchRequested = true
            return
        }
        isFetchingRuns = true
        defer { isFetchingRuns = false }

        repeat {
            refetchRequested = false
            await fetchRunsOnce(manageLoading: manageLoading)
        } while refetchRequested && !Task.isCancelled
    }

    private func fetchRunsOnce(manageLoading: Bool) async {
        guard let token = KeychainService.loadToken() else {
            isAuthenticated = false
            return
        }

        if manageLoading && !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil
        defer { if manageLoading { isLoading = false } }
        let sessionID = self.sessionID

        do {
            let query = runQueryAtSettingsOpen ?? settings.runQuery
            let usingFallback = query.repoNames.isEmpty
            let repos = usingFallback ? nil : Array(query.repoNames)
            let actor = query.includeRunsFromOtherUsers ? nil : username
            let recentRuns = try await apiClient.fetchRecentRuns(token: token, actor: actor, repos: repos)
            let newRuns = recentRuns.runs

            guard sessionID == self.sessionID else { return }
            // Settings closed with changes while this was in flight; these results are for the old ones.
            guard query == runQueryAtSettingsOpen ?? settings.runQuery else {
                refetchRequested = true
                return
            }

            // With nothing selected yet, adopt the repos that have recent runs as the selection.
            // Not while Settings is open, where it would overwrite the user's edits.
            if usingFallback && runQueryAtSettingsOpen == nil && !newRuns.isEmpty {
                settings.selectedRepoNames = Set(newRuns.map(\.repositoryFullName))
            }

            let workflowFilteredRuns = newRuns.filtered(by: query.workflowFilterMode, patterns: query.workflowFilterText)
            let visibleRuns = workflowFilteredRuns.limited(toRunsPerRepo: query.maxRunsPerRepo)

            if hasLoadedOnce {
                for run in runHistory.newlyCompleted(in: visibleRuns) {
                    NotificationService.sendCompletionNotification(run: run)
                }
            }
            // Track every fetched run, not just the visible ones, so a run hidden by the filter or
            // the per-repo limit for one fetch still notifies if it shows up completed later.
            runHistory.record(newRuns, keepingRunsFrom: recentRuns.failedRepos)

            overallStatus = workflowFilteredRuns.overallStatus
            runs = visibleRuns
            failedRepos = recentRuns.failedRepos
            hasLoadedOnce = true
        } catch let error where error is CancellationError || Task.isCancelled {
            // Task was cancelled (e.g. polling restart) — don't surface to UI. Requests cut off
            // by the cancellation can surface as network errors, hence the `Task.isCancelled` check.
        } catch GitHubAPIError.invalidToken {
            guard sessionID == self.sessionID else { return }
            signOut()
        } catch {
            guard sessionID == self.sessionID else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Repositories

    func fetchAvailableRepos(force: Bool = false) {
        guard let token = KeychainService.loadToken() else { return }
        if !force && !availableRepos.isEmpty { return }
        isLoadingRepos = true
        repoListError = nil
        let sessionID = self.sessionID
        // Only the latest load applies its result, so an older one finishing later can't overwrite it.
        repoListTask?.cancel()
        repoListTask = Task {
            do {
                let repos = try await apiClient.fetchAllRepos(token: token)
                guard !Task.isCancelled, sessionID == self.sessionID else { return }
                availableRepos = repos
                repoListIsCapped = repos.count >= GitHubAPIClient.maxRepositories
            } catch {
                guard !Task.isCancelled, sessionID == self.sessionID else { return }
                // Keep whatever list we had before.
                repoListError = error.localizedDescription
            }
            isLoadingRepos = false
        }
    }
}
