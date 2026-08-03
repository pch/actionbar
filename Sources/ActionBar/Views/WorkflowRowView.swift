import SwiftUI

struct WorkflowRowView: View {
    let run: WorkflowRun
    var now: Date = Date()
    var showsTriggeringActor = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            StatusDotView(status: RunStatus(from: run))

            VStack(alignment: .leading, spacing: 2) {
                Text(run.displayTitle ?? run.name ?? "Workflow")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(repoName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    if showsTriggeringActor, let login = run.triggeringActorLogin {
                        metadataSeparator
                        Text("@\(login)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let branch = run.headBranch {
                        metadataSeparator
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Text(RelativeTime.format(run.updatedAt, relativeTo: now))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
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
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if let url = URL(string: run.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var metadataSeparator: some View {
        Text("·")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
    }

    private var repoName: String {
        // Show only repo name (without owner) to save space
        if let slashIndex = run.repositoryFullName.firstIndex(of: "/") {
            return String(run.repositoryFullName[run.repositoryFullName.index(after: slashIndex)...])
        }
        return run.repositoryFullName
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
