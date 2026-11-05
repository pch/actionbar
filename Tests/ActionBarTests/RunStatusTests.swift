import Foundation
import Testing

struct RunStatusTests {
    @Test(arguments: [
        ("in_progress", RunStatus.running),
        ("queued", .queued),
        ("waiting", .queued),
        ("pending", .queued),
        ("requested", .queued),
    ])
    func activeStatuses(status: String, expected: RunStatus) {
        let status = RunStatus(from: .make(status: status, conclusion: nil))
        #expect(status == expected)
        #expect(status.isActive)
    }

    @Test(arguments: [
        ("success", RunStatus.success),
        ("failure", .failure),
        ("timed_out", .failure),
        ("startup_failure", .failure),
        ("cancelled", .cancelled),
        ("skipped", .cancelled),
        ("neutral", .unknown),
    ])
    func completedConclusions(conclusion: String, expected: RunStatus) {
        let status = RunStatus(from: .make(status: "completed", conclusion: conclusion))
        #expect(status == expected)
        #expect(!status.isActive)
    }

    @Test func completedWithoutConclusionIsUnknown() {
        #expect(RunStatus(from: .make(status: "completed", conclusion: nil)) == .unknown)
    }

    @Test func unrecognizedOrMissingStatusIsUnknown() {
        #expect(RunStatus(from: .make(status: "something_new", conclusion: nil)) == .unknown)
        #expect(RunStatus(from: .make(status: nil, conclusion: nil)) == .unknown)
    }

    // MARK: - Overall Status

    @Test func overallStatusOfNoRunsIsUnknown() {
        #expect([WorkflowRun]().overallStatus == .unknown)
    }

    @Test func overallStatusIsRunningWhileAnythingIsActive() {
        let runs: [WorkflowRun] = [
            .make(id: 1, conclusion: "failure", updatedAt: Date(timeIntervalSince1970: 200)),
            .make(id: 2, status: "waiting", conclusion: nil, updatedAt: Date(timeIntervalSince1970: 100)),
        ]
        #expect(runs.overallStatus == .running)
    }

    @Test func overallStatusFollowsMostRecentlyFinishedRun() {
        let runs: [WorkflowRun] = [
            .make(id: 1, conclusion: "success", updatedAt: Date(timeIntervalSince1970: 100)),
            .make(id: 2, conclusion: "failure", updatedAt: Date(timeIntervalSince1970: 300)),
            .make(id: 3, conclusion: "cancelled", updatedAt: Date(timeIntervalSince1970: 200)),
        ]
        #expect(runs.overallStatus == .failure)
    }

    @Test func overallStatusIgnoresRunsThatAreNeitherActiveNorCompleted() {
        let runs: [WorkflowRun] = [
            .make(id: 1, conclusion: "success", updatedAt: Date(timeIntervalSince1970: 100)),
            .make(id: 2, status: "something_new", conclusion: nil, updatedAt: Date(timeIntervalSince1970: 300)),
        ]
        #expect(runs.overallStatus == .success)
    }
}
