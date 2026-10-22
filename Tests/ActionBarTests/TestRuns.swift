import Foundation

extension WorkflowRun {
    static func make(
        id: Int = 1,
        name: String? = "CI",
        status: String? = "completed",
        conclusion: String? = "success",
        updatedAt: Date = Date(timeIntervalSince1970: 0),
        repo: String = "owner/repo"
    ) -> WorkflowRun {
        WorkflowRun(
            id: id,
            name: name,
            displayTitle: nil,
            status: status,
            conclusion: conclusion,
            htmlUrl: "https://github.com/\(repo)/actions/runs/\(id)",
            headBranch: "main",
            updatedAt: updatedAt,
            repositoryFullName: repo
        )
    }
}
