import Foundation
import Observation

/// The user's preferences, saved to `UserDefaults` as soon as they change.
@MainActor
@Observable
final class SettingsStore {
    static let defaultPollingInterval: TimeInterval = 30
    static let defaultMaxRunsPerRepo = 5

    /// The settings that decide which runs are fetched and shown.
    struct RunQuery: Equatable {
        var repoNames: Set<String>
        var workflowFilterMode: WorkflowFilterMode
        var workflowFilterText: String
        var maxRunsPerRepo: Int
        var includeRunsFromOtherUsers: Bool
    }

    var selectedRepoNames: Set<String> = [] {
        didSet { save(Array(selectedRepoNames), forKey: Key.selectedRepos) }
    }
    var pollingInterval = SettingsStore.defaultPollingInterval {
        didSet { save(pollingInterval, forKey: Key.pollingInterval) }
    }
    var workflowFilterMode: WorkflowFilterMode = .off {
        didSet { save(workflowFilterMode.rawValue, forKey: Key.workflowFilterMode) }
    }
    var workflowFilterText = "" {
        didSet { save(workflowFilterText, forKey: Key.workflowFilterText) }
    }
    var maxRunsPerRepo = SettingsStore.defaultMaxRunsPerRepo {
        didSet { save(maxRunsPerRepo, forKey: Key.maxRunsPerRepo) }
    }
    var includeRunsFromOtherUsers = false {
        didSet { save(includeRunsFromOtherUsers, forKey: Key.includeRunsFromOtherUsers) }
    }

    var runQuery: RunQuery {
        RunQuery(
            repoNames: selectedRepoNames,
            workflowFilterMode: workflowFilterMode,
            workflowFilterText: workflowFilterText,
            maxRunsPerRepo: maxRunsPerRepo,
            includeRunsFromOtherUsers: includeRunsFromOtherUsers
        )
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// `@Observable` runs `didSet` even for assignments in `init`; this keeps loading from writing back.
    @ObservationIgnored private var isLoading = true

    private enum Key {
        static let selectedRepos = "selectedRepositories"
        static let pollingInterval = "pollingInterval"
        static let workflowFilterMode = "workflowFilterMode"
        static let workflowFilterText = "workflowFilterText"
        static let maxRunsPerRepo = "maxRunsPerRepo"
        static let includeRunsFromOtherUsers = "includeRunsFromOtherUsers"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let saved = defaults.stringArray(forKey: Key.selectedRepos) {
            selectedRepoNames = Set(saved)
        }

        let savedInterval = defaults.double(forKey: Key.pollingInterval)
        pollingInterval = savedInterval > 0 ? savedInterval : Self.defaultPollingInterval

        if let modeRaw = defaults.string(forKey: Key.workflowFilterMode),
           let mode = WorkflowFilterMode(rawValue: modeRaw) {
            workflowFilterMode = mode
        }
        workflowFilterText = defaults.string(forKey: Key.workflowFilterText) ?? ""

        let savedMaxRuns = defaults.integer(forKey: Key.maxRunsPerRepo)
        maxRunsPerRepo = savedMaxRuns > 0 ? savedMaxRuns : Self.defaultMaxRunsPerRepo

        includeRunsFromOtherUsers = defaults.bool(forKey: Key.includeRunsFromOtherUsers)
        isLoading = false
    }

    private func save(_ value: Any, forKey key: String) {
        guard !isLoading else { return }
        defaults.set(value, forKey: key)
    }

    /// Forgets everything tied to the signed-in account.
    /// The polling interval is a device preference, so it survives signing out.
    func resetAccountSettings() {
        selectedRepoNames = []
        workflowFilterMode = .off
        workflowFilterText = ""
        maxRunsPerRepo = Self.defaultMaxRunsPerRepo
        includeRunsFromOtherUsers = false
        for key in [
            Key.selectedRepos,
            Key.workflowFilterMode,
            Key.workflowFilterText,
            Key.maxRunsPerRepo,
            Key.includeRunsFromOtherUsers,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Repository Selection

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
}
