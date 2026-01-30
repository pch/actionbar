import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var runs: [WorkflowRun] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var username: String?

    private let apiClient = GitHubAPIClient()
    private var pollTimer: Timer?
    private var previousRunStates: [Int: String] = [:] // run.id -> status/conclusion
    private var hasLoadedOnce = false

    var overallStatus: RunStatus {
        guard let newest = runs.first else { return .unknown }
        return RunStatus(from: newest)
    }

    func start() {
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

    func signOut() {
        stopPolling()
        KeychainService.deleteToken()
        isAuthenticated = false
        runs = []
        username = nil
        previousRunStates = [:]
        hasLoadedOnce = false
        errorMessage = nil
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
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
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
        guard let token = KeychainService.loadToken() else {
            isAuthenticated = false
            return
        }

        if !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil

        do {
            let newRuns = try await apiClient.fetchRecentRuns(token: token, actor: username)

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
}
