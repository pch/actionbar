import SwiftUI

struct WorkflowRowView: View {
    let run: WorkflowRun
    var now: Date = Date()

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

                    if let branch = run.headBranch {
                        Text("·")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
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

    private var repoName: String {
        // Show only repo name (without owner) to save space
        if let slashIndex = run.repositoryFullName.firstIndex(of: "/") {
            return String(run.repositoryFullName[run.repositoryFullName.index(after: slashIndex)...])
        }
        return run.repositoryFullName
    }
}
