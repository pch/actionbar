import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
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
    @Published var pollingInterval: TimeInterval = 30

    private let apiClient = GitHubAPIClient()
    private let oauthService = OAuthService()
    private var pollTimer: Timer?
    private var oauthTask: Task<Void, Never>?
    private var previousRunStates: [Int: String] = [:] // run.id -> status/conclusion
    private var hasLoadedOnce = false
    private var isFetchingRuns = false

    private static let selectedReposKey = "selectedRepositories"
    private static let pollingIntervalKey = "pollingInterval"

    var hasRepoConfiguration: Bool {
        UserDefaults.standard.object(forKey: Self.selectedReposKey) != nil
    }

    var overallStatus: RunStatus {
        guard let newest = runs.first else { return .unknown }
        return RunStatus(from: newest)
    }

    func start() {
        loadSelectedRepos()
        loadPollingInterval()
        guard let token = KeychainService.loadToken() else { return }
        isAuthenticated = true
        // Fetch username for actor-filtered polling, then start
        Task {
            if let user = try? await apiClient.validateToken(token) {
                username = user.login
            }
            startPolling()
        }
    }

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
                guard KeychainService.saveToken(token) else {
                    throw GitHubAPIError.networkError(
                        NSError(domain: "KeychainError", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to save token to Keychain"])
                    )
                }

                username = user.login
                isAuthenticated = true
                deviceCode = nil
                isLoggingIn = false
                startPolling()
            } catch is CancellationError {
                deviceCode = nil
                isLoggingIn = false
            } catch {
                errorMessage = error.localizedDescription
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
        KeychainService.deleteToken()
        isAuthenticated = false
        runs = []
        username = nil
        previousRunStates = [:]
        hasLoadedOnce = false
        errorMessage = nil
        selectedRepoNames = []
        availableRepos = []
        repoListIsCapped = false
        showingSettings = false
        UserDefaults.standard.removeObject(forKey: Self.selectedReposKey)
    }

    func authenticate(token: String) async throws {
        let user = try await apiClient.validateToken(token)
        guard KeychainService.saveToken(token) else {
            throw GitHubAPIError.networkError(
                NSError(domain: "KeychainError", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to save token to Keychain"])
            )
        }
        username = user.login
        isAuthenticated = true
        startPolling()
    }

    func refreshNow() {
        Task { await fetchRuns() }
    }

    // MARK: - Polling

    private func startPolling() {
        fetchRunsInitial()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchRuns()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchRunsInitial() {
        Task { await fetchRuns() }
    }

    private func fetchRuns() async {
        guard !isFetchingRuns else { return }
        isFetchingRuns = true
        defer { isFetchingRuns = false }

        guard let token = KeychainService.loadToken() else {
            isAuthenticated = false
            return
        }

        if !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil

        do {
            let usingFallback = !hasRepoConfiguration || selectedRepoNames.isEmpty
            let repos = usingFallback ? nil : Array(selectedRepoNames)
            let newRuns = try await apiClient.fetchRecentRuns(token: token, actor: username, repos: repos)

            if usingFallback && !newRuns.isEmpty {
                let repoNames = Set(newRuns.map(\.repositoryFullName))
                selectedRepoNames = repoNames
                saveSelectedRepos()
            }

            // Detect completions for notifications
            if hasLoadedOnce {
                detectCompletions(newRuns: newRuns)
            }

            // Update state tracking
            previousRunStates = [:]
            for run in newRuns {
                previousRunStates[run.id] = stateKey(for: run)
            }

            runs = newRuns
            hasLoadedOnce = true
            isLoading = false
        } catch let error as GitHubAPIError {
            if case .invalidToken = error {
                signOut()
            } else {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    // MARK: - Completion Detection

    private func detectCompletions(newRuns: [WorkflowRun]) {
        for run in newRuns {
            let newState = stateKey(for: run)
            if let oldState = previousRunStates[run.id], oldState != newState {
                let status = RunStatus(from: run)
                if run.status == "completed" && (oldState.hasPrefix("in_progress") || oldState.hasPrefix("queued")) {
                    NotificationService.sendCompletionNotification(run: run)
                    _ = status // suppress unused warning
                }
            }
        }
    }

    private func stateKey(for run: WorkflowRun) -> String {
        "\(run.status ?? "unknown")/\(run.conclusion ?? "none")"
    }

    // MARK: - Settings Persistence

    private func loadSelectedRepos() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectedReposKey) {
            selectedRepoNames = Set(saved)
        }
    }

    func saveSelectedRepos() {
        UserDefaults.standard.set(Array(selectedRepoNames), forKey: Self.selectedReposKey)
    }

    func snapshotSelectedRepos() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectedReposKey) {
            repoSelectionSnapshot = Set(saved)
        } else {
            repoSelectionSnapshot = []
        }
    }

    func resetReposToSnapshot() {
        selectedRepoNames = repoSelectionSnapshot
    }

    private func loadPollingInterval() {
        let saved = UserDefaults.standard.double(forKey: Self.pollingIntervalKey)
        pollingInterval = saved > 0 ? saved : 30
    }

    private func savePollingInterval() {
        UserDefaults.standard.set(pollingInterval, forKey: Self.pollingIntervalKey)
    }

    func updatePollingInterval(_ interval: TimeInterval) {
        pollingInterval = interval
        savePollingInterval()
        stopPolling()
        startPolling()
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
            do {
                let repos = try await apiClient.fetchAllRepos(token: token)
                availableRepos = repos
                repoListIsCapped = repos.count >= 200
            } catch {
                // Keep whatever we had before
            }
            isLoadingRepos = false
        }
    }
}
