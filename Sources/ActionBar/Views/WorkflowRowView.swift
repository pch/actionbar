import SwiftUI

struct WorkflowRowView: View {
    let run: WorkflowRun
    var now = Date()
    var showsTriggeringActor = false

    @Environment(\.openURL) private var openURL
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: run.htmlUrl) {
                openURL(url)
            }
        } label: {
            content
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var content: some View {
        HStack(spacing: 8) {
            StatusDotView(status: RunStatus(from: run))

            VStack(alignment: .leading, spacing: 2) {
                Text(run.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(repoName)

                    if showsTriggeringActor, let login = run.triggeringActorLogin {
                        metadataSeparator
                        Text("@\(login)")
                            .lineLimit(1)
                    }

                    if let branch = run.headBranch {
                        metadataSeparator
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(RelativeTime.format(run.updatedAt, relativeTo: now))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        )
        .contentShape(Rectangle())
    }

    private var metadataSeparator: some View {
        Text("·")
    }

    /// The repository name without its owner, to save space.
    private var repoName: String {
        run.repositoryFullName.split(separator: "/", maxSplits: 1).last.map(String.init) ?? run.repositoryFullName
    }
}

#Preview {
    WorkflowRowView(
        run: WorkflowRun(
            id: 1,
            name: "CI",
            displayTitle: "Fix login bug",
            status: "completed",
            conclusion: "success",
            htmlUrl: "https://github.com/owner/repo/actions/runs/1",
            headBranch: "main",
            updatedAt: Date().addingTimeInterval(-300),
            repositoryFullName: "owner/repo",
            triggeringActorLogin: "octocat"
        ),
        showsTriggeringActor: true
    )
}

#Preview("Failure") {
    WorkflowRowView(
        run: WorkflowRun(
            id: 2,
            name: "Tests",
            displayTitle: "Update dependencies",
            status: "completed",
            conclusion: "failure",
            htmlUrl: "https://github.com/owner/repo/actions/runs/2",
            headBranch: "feature/auth",
            updatedAt: Date().addingTimeInterval(-60),
            repositoryFullName: "owner/repo"
        )
    )
}

#Preview("Running") {
    WorkflowRowView(
        run: WorkflowRun(
            id: 3,
            name: "Deploy",
            displayTitle: "Deploy to production",
            status: "in_progress",
            conclusion: nil,
            htmlUrl: "https://github.com/owner/repo/actions/runs/3",
            headBranch: "main",
            updatedAt: Date(),
            repositoryFullName: "owner/repo"
        )
    )
}
