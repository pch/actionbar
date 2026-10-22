import Foundation
import Testing

struct WorkflowRunListTests {
    private let runs: [WorkflowRun] = [
        .make(id: 1, name: "CI"),
        .make(id: 2, name: "Deploy to production"),
        .make(id: 3, name: "Build docs"),
        .make(id: 4, name: nil),
    ]

    // MARK: - Workflow Filter

    @Test func filterOffKeepsEverything() {
        #expect(runs.filtered(by: .off, patterns: "ci").map(\.id) == [1, 2, 3, 4])
    }

    @Test func includeKeepsMatchingNames() {
        #expect(runs.filtered(by: .include, patterns: "ci, DEPLOY").map(\.id) == [1, 2])
    }

    @Test func excludeDropsMatchingNames() {
        #expect(runs.filtered(by: .exclude, patterns: "ci,deploy").map(\.id) == [3, 4])
    }

    @Test func matchesSubstrings() {
        #expect(runs.filtered(by: .include, patterns: "prod").map(\.id) == [2])
    }

    @Test(arguments: [WorkflowFilterMode.include, .exclude])
    func blankPatternsKeepEverything(mode: WorkflowFilterMode) {
        #expect(runs.filtered(by: mode, patterns: "").map(\.id) == [1, 2, 3, 4])
        #expect(runs.filtered(by: mode, patterns: " , ,").map(\.id) == [1, 2, 3, 4])
    }

    // MARK: - Runs per Repo

    @Test func limitsRunsPerRepoPreservingOrder() {
        let runs: [WorkflowRun] = [
            .make(id: 1, repo: "owner/a"),
            .make(id: 2, repo: "owner/b"),
            .make(id: 3, repo: "owner/a"),
            .make(id: 4, repo: "owner/a"),
            .make(id: 5, repo: "owner/b"),
            .make(id: 6, repo: "owner/b"),
        ]
        #expect(runs.limited(toRunsPerRepo: 2).map(\.id) == [1, 2, 3, 5])
        #expect(runs.limited(toRunsPerRepo: 1).map(\.id) == [1, 2])
        #expect(runs.limited(toRunsPerRepo: 10).map(\.id) == [1, 2, 3, 4, 5, 6])
    }

    // MARK: - Completion Notifications

    private func history(_ runs: [WorkflowRun], failedRepos: [String] = []) -> RunHistory {
        var history = RunHistory()
        history.record(runs, keepingRunsFrom: failedRepos)
        return history
    }

    @Test(arguments: ["in_progress", "queued", "waiting", "pending", "requested"])
    func notifiesWhenActiveRunCompletes(previousStatus: String) {
        let history = history([.make(id: 1, status: previousStatus, conclusion: nil)])
        let completed = [WorkflowRun.make(id: 1, conclusion: "failure")]
        #expect(history.newlyCompleted(in: completed).map(\.id) == [1])
    }

    @Test func doesNotNotifyForRunsAlreadyFinished() {
        let history = history([.make(id: 1)])
        #expect(history.newlyCompleted(in: [.make(id: 1)]).isEmpty)
    }

    @Test func doesNotNotifyForRunsNotSeenBefore() {
        #expect(RunHistory().newlyCompleted(in: [.make(id: 1)]).isEmpty)
    }

    @Test func doesNotNotifyForRunsStillActive() {
        let history = history([.make(id: 1, status: "queued", conclusion: nil)])
        let runs = [WorkflowRun.make(id: 1, status: "in_progress", conclusion: nil)]
        #expect(history.newlyCompleted(in: runs).isEmpty)
    }

    @Test func forgetsRunsThatAreNoLongerFetched() {
        var history = history([.make(id: 1, status: "in_progress", conclusion: nil)])
        history.record([], keepingRunsFrom: [])
        #expect(history.newlyCompleted(in: [.make(id: 1)]).isEmpty)
    }

    @Test func keepsRunsFromReposThatFailedToLoad() {
        var history = history([
            .make(id: 1, status: "in_progress", conclusion: nil, repo: "owner/a"),
            .make(id: 2, status: "in_progress", conclusion: nil, repo: "owner/b"),
        ])
        history.record([], keepingRunsFrom: ["owner/a"])

        let completed: [WorkflowRun] = [.make(id: 1, repo: "owner/a"), .make(id: 2, repo: "owner/b")]
        #expect(history.newlyCompleted(in: completed).map(\.id) == [1])
    }

    @Test func freshResultsReplaceKeptRuns() {
        var history = history([.make(id: 1, status: "in_progress", conclusion: nil, repo: "owner/a")])
        history.record([.make(id: 1, repo: "owner/a")], keepingRunsFrom: ["owner/a"])
        #expect(history.newlyCompleted(in: [.make(id: 1, repo: "owner/a")]).isEmpty)
    }
}
