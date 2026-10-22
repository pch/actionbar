import Foundation
import Testing

/// Each test starts from an empty defaults suite. They share one suite, so they run one at a time.
@MainActor
@Suite(.serialized)
final class SettingsStoreTests {
    private let suiteName = "com.ptrchm.actionbar.tests"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func defaultsWhenNothingIsSaved() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.selectedRepoNames.isEmpty)
        #expect(store.pollingInterval == SettingsStore.defaultPollingInterval)
        #expect(store.workflowFilterMode == .off)
        #expect(store.workflowFilterText == "")
        #expect(store.maxRunsPerRepo == SettingsStore.defaultMaxRunsPerRepo)
        #expect(!store.includeRunsFromOtherUsers)
    }

    @Test func loadingDoesNotWriteAnything() {
        _ = SettingsStore(defaults: defaults)
        #expect(defaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
    }

    @Test func changesAreSavedImmediately() {
        let store = SettingsStore(defaults: defaults)
        store.selectedRepoNames = ["owner/a", "owner/b"]
        store.pollingInterval = 60
        store.workflowFilterMode = .exclude
        store.workflowFilterText = "deploy"
        store.maxRunsPerRepo = 3
        store.includeRunsFromOtherUsers = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.selectedRepoNames == ["owner/a", "owner/b"])
        #expect(reloaded.pollingInterval == 60)
        #expect(reloaded.workflowFilterMode == .exclude)
        #expect(reloaded.workflowFilterText == "deploy")
        #expect(reloaded.maxRunsPerRepo == 3)
        #expect(reloaded.includeRunsFromOtherUsers)
    }

    @Test func repoSelectionHelpers() {
        let store = SettingsStore(defaults: defaults)
        store.toggleRepo("owner/a")
        store.toggleRepo("owner/b")
        store.toggleRepo("owner/a")
        #expect(SettingsStore(defaults: defaults).selectedRepoNames == ["owner/b"])

        store.selectAllRepos(["owner/a", "owner/c"])
        #expect(SettingsStore(defaults: defaults).selectedRepoNames == ["owner/a", "owner/c"])

        store.deselectAllRepos()
        #expect(SettingsStore(defaults: defaults).selectedRepoNames.isEmpty)
    }

    @Test func runQueryReflectsCurrentSettings() {
        let store = SettingsStore(defaults: defaults)
        store.selectedRepoNames = ["owner/a"]
        store.workflowFilterMode = .include
        store.workflowFilterText = "ci"
        store.maxRunsPerRepo = 2
        store.includeRunsFromOtherUsers = true

        #expect(store.runQuery == SettingsStore.RunQuery(
            repoNames: ["owner/a"],
            workflowFilterMode: .include,
            workflowFilterText: "ci",
            maxRunsPerRepo: 2,
            includeRunsFromOtherUsers: true
        ))
    }

    @Test func invalidSavedValuesFallBackToDefaults() {
        defaults.set(0, forKey: "pollingInterval")
        defaults.set(-1, forKey: "maxRunsPerRepo")
        defaults.set("bogus", forKey: "workflowFilterMode")

        let store = SettingsStore(defaults: defaults)
        #expect(store.pollingInterval == SettingsStore.defaultPollingInterval)
        #expect(store.maxRunsPerRepo == SettingsStore.defaultMaxRunsPerRepo)
        #expect(store.workflowFilterMode == .off)
    }

    @Test func resetAccountSettingsKeepsPollingInterval() {
        let store = SettingsStore(defaults: defaults)
        store.selectedRepoNames = ["owner/a"]
        store.pollingInterval = 300
        store.workflowFilterMode = .include
        store.workflowFilterText = "ci"
        store.maxRunsPerRepo = 2
        store.includeRunsFromOtherUsers = true

        store.resetAccountSettings()

        #expect(store.selectedRepoNames.isEmpty)
        #expect(store.pollingInterval == 300)
        #expect(store.workflowFilterMode == .off)
        #expect(store.workflowFilterText == "")
        #expect(store.maxRunsPerRepo == SettingsStore.defaultMaxRunsPerRepo)
        #expect(!store.includeRunsFromOtherUsers)
        #expect(defaults.persistentDomain(forName: suiteName)?.keys.sorted() == ["pollingInterval"])
    }
}
