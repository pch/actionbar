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

    @Test(arguments: ["in_progress", "queued", "waiting", "pending", "requested"])
    func notifiesWhenActiveRunCompletes(previousStatus: String) {
        let previous = [1: RunStatus(from: .make(status: previousStatus, conclusion: nil))]
        let completed = [WorkflowRun.make(id: 1, conclusion: "failure")]
        #expect(completed.newlyCompleted(since: previous).map(\.id) == [1])
    }

    @Test func doesNotNotifyForRunsAlreadyFinished() {
        let previous: [Int: RunStatus] = [1: .success]
        #expect([WorkflowRun.make(id: 1)].newlyCompleted(since: previous).isEmpty)
    }

    @Test func doesNotNotifyForRunsNotSeenBefore() {
        #expect([WorkflowRun.make(id: 1)].newlyCompleted(since: [:]).isEmpty)
    }

    @Test func doesNotNotifyForRunsStillActive() {
        let previous: [Int: RunStatus] = [1: .queued]
        let runs = [WorkflowRun.make(id: 1, status: "in_progress", conclusion: nil)]
        #expect(runs.newlyCompleted(since: previous).isEmpty)
    }
}
