import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
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
    @Published var pollingInterval: TimeInterval = 30
    @Published var workflowFilterMode: WorkflowFilterMode = .off
    @Published var workflowFilterText: String = ""
    @Published var maxRunsPerRepo: Int = 5

    private let apiClient = GitHubAPIClient()
    private let oauthService = OAuthService()
    private var pollTask: Task<Void, Never>?
    private var installCheckTask: Task<Void, Never>?
    private var oauthTask: Task<Void, Never>?
    private var previousRunStates: [Int: String] = [:] // run.id -> status/conclusion
    private var hasLoadedOnce = false
    private var isFetchingRuns = false

    private static let selectedReposKey = "selectedRepositories"
    private static let pollingIntervalKey = "pollingInterval"
    private static let workflowFilterModeKey = "workflowFilterMode"
    private static let workflowFilterTextKey = "workflowFilterText"
    private static let maxRunsPerRepoKey = "maxRunsPerRepo"

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
        loadWorkflowFilter()
        loadMaxRunsPerRepo()
        guard let token = KeychainService.loadToken() else { return }
        isAuthenticated = true
        Task {
            if let user = try? await apiClient.validateToken(token) {
                username = user.login
            }

            do {
                let hasInstalls = try await apiClient.hasInstallations(token: token)
                if hasInstalls {
                    startPolling()
                } else {
                    needsInstallation = true
                    startInstallCheckTimer()
                }
            } catch {
                // API call failed — don't assume no installations.
                // Start polling; fetchRuns will surface real errors.
                startPolling()
            }
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

                do {
                    let hasInstalls = try await apiClient.hasInstallations(token: token)
                    if hasInstalls {
                        startPolling()
                    } else {
                        needsInstallation = true
                        startInstallCheckTimer()
                    }
                } catch {
                    // Installation check failed after login — start polling anyway
                    startPolling()
                }
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

    func openInstallationPage() {
        if let url = URL(string: "https://github.com/apps/actionbar-macos") {
            NSWorkspace.shared.open(url)
        }
    }

    func checkInstallationAndStart() {
        guard let token = KeychainService.loadToken() else { return }
        isCheckingInstallation = true
        Task {
            do {
                let hasInstalls = try await apiClient.hasInstallations(token: token)
                if hasInstalls {
                    stopInstallCheckTimer()
                    needsInstallation = false
                    errorMessage = nil
                    startPolling()
                } else {
                    errorMessage = "No installation found yet. Please install the app on GitHub first. If you did, wait a bit."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isCheckingInstallation = false
        }
    }

    func startInstallCheckTimer() {
        stopInstallCheckTimer()
        installCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                guard let token = KeychainService.loadToken() else { continue }
                let hasInstalls = (try? await apiClient.hasInstallations(token: token)) ?? false
                if hasInstalls {
                    needsInstallation = false
                    errorMessage = nil
                    startPolling()
                    break
                }
            }
        }
    }

    private func stopInstallCheckTimer() {
        installCheckTask?.cancel()
        installCheckTask = nil
    }

    func signOut() {
        cancelLogin()
        stopPolling()
        stopInstallCheckTimer()
        KeychainService.deleteToken()
        isAuthenticated = false
        needsInstallation = false
        runs = []
        username = nil
        previousRunStates = [:]
        hasLoadedOnce = false
        errorMessage = nil
        selectedRepoNames = []
        availableRepos = []
        repoListIsCapped = false
        showingSettings = false
        workflowFilterMode = .off
        workflowFilterText = ""
        maxRunsPerRepo = 5
        UserDefaults.standard.removeObject(forKey: Self.selectedReposKey)
        UserDefaults.standard.removeObject(forKey: Self.workflowFilterModeKey)
        UserDefaults.standard.removeObject(forKey: Self.workflowFilterTextKey)
        UserDefaults.standard.removeObject(forKey: Self.maxRunsPerRepoKey)
    }

    func refreshNow() {
        isLoading = true
        Task {
            let start = Date()
            await fetchRuns(manageLoading: false)
            let elapsed = Date().timeIntervalSince(start)
            let remaining = 0.5 - elapsed
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            isLoading = false
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTask = Task {
            await fetchRuns()
            while !Task.isCancelled {
                let deadline = Date().addingTimeInterval(pollingInterval)
                while Date() < deadline, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
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
            let newRuns = try await apiClient.fetchRecentRuns(token: token, actor: username, repos: repos)

            if usingFallback && !newRuns.isEmpty {
                let repoNames = Set(newRuns.map(\.repositoryFullName))
                selectedRepoNames = repoNames
                saveSelectedRepos()
            }

            let filteredRuns = applyMaxRunsPerRepo(to: applyWorkflowFilter(to: newRuns))

            // Detect completions for notifications
            if hasLoadedOnce {
                detectCompletions(newRuns: filteredRuns)
            }

            // Update state tracking
            previousRunStates = [:]
            for run in filteredRuns {
                previousRunStates[run.id] = stateKey(for: run)
            }

            runs = filteredRuns
            hasLoadedOnce = true
            if manageLoading { isLoading = false }
        } catch let error as GitHubAPIError {
            if case .invalidToken = error {
                signOut()
            } else {
                errorMessage = error.localizedDescription
                if manageLoading { isLoading = false }
            }
        } catch is CancellationError {
            // Task was cancelled (e.g. polling restart) — don't surface to UI.
            if manageLoading { isLoading = false }
        } catch {
            errorMessage = error.localizedDescription
            if manageLoading { isLoading = false }
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

    private func loadWorkflowFilter() {
        if let modeRaw = UserDefaults.standard.string(forKey: Self.workflowFilterModeKey),
           let mode = WorkflowFilterMode(rawValue: modeRaw) {
            workflowFilterMode = mode
        }
        workflowFilterText = UserDefaults.standard.string(forKey: Self.workflowFilterTextKey) ?? ""
    }

    func saveWorkflowFilter() {
        UserDefaults.standard.set(workflowFilterMode.rawValue, forKey: Self.workflowFilterModeKey)
        UserDefaults.standard.set(workflowFilterText, forKey: Self.workflowFilterTextKey)
    }

    private func applyWorkflowFilter(to runs: [WorkflowRun]) -> [WorkflowRun] {
        guard workflowFilterMode != .off else { return runs }

        let patterns = workflowFilterText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        guard !patterns.isEmpty else { return runs }

        return runs.filter { run in
            let name = (run.name ?? "").lowercased()
            let matches = patterns.contains { name.contains($0) }
            return workflowFilterMode == .include ? matches : !matches
        }
    }

    private func loadMaxRunsPerRepo() {
        let saved = UserDefaults.standard.integer(forKey: Self.maxRunsPerRepoKey)
        maxRunsPerRepo = saved > 0 ? saved : 5
    }

    func saveMaxRunsPerRepo() {
        UserDefaults.standard.set(maxRunsPerRepo, forKey: Self.maxRunsPerRepoKey)
    }

    private func applyMaxRunsPerRepo(to runs: [WorkflowRun]) -> [WorkflowRun] {
        var countsByRepo: [String: Int] = [:]
        return runs.filter { run in
            let count = countsByRepo[run.repositoryFullName, default: 0]
            guard count < maxRunsPerRepo else { return false }
            countsByRepo[run.repositoryFullName] = count + 1
            return true
        }
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
