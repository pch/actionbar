import Foundation
import Observation

/// The user's preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class SettingsStore {
    static let defaultPollingInterval: TimeInterval = 30
    static let defaultMaxRunsPerRepo = 5

    var selectedRepoNames: Set<String> = []
    var pollingInterval = SettingsStore.defaultPollingInterval {
        didSet { if !isLoading { defaults.set(pollingInterval, forKey: Key.pollingInterval) } }
    }
    var workflowFilterMode: WorkflowFilterMode = .off
    var workflowFilterText = ""
    var maxRunsPerRepo = SettingsStore.defaultMaxRunsPerRepo
    var includeRunsFromOtherUsers = false

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

    /// Whether a repository selection has ever been saved.
    var hasRepoConfiguration: Bool {
        defaults.object(forKey: Key.selectedRepos) != nil
    }

    var savedSelectedRepoNames: Set<String> {
        Set(defaults.stringArray(forKey: Key.selectedRepos) ?? [])
    }

    /// Persists the settings edited in the settings panel. The polling interval is saved as soon as it changes.
    func save() {
        saveSelectedRepos()
        defaults.set(workflowFilterMode.rawValue, forKey: Key.workflowFilterMode)
        defaults.set(workflowFilterText, forKey: Key.workflowFilterText)
        defaults.set(maxRunsPerRepo, forKey: Key.maxRunsPerRepo)
        defaults.set(includeRunsFromOtherUsers, forKey: Key.includeRunsFromOtherUsers)
    }

    func saveSelectedRepos() {
        defaults.set(Array(selectedRepoNames), forKey: Key.selectedRepos)
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
