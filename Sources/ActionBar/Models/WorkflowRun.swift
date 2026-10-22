import Foundation

struct WorkflowRun: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?
    let conclusion: String?
    let event: String?
    let htmlUrl: String
    let headBranch: String?
    let createdAt: Date
    let updatedAt: Date
    let repositoryFullName: String
    let triggeringActorLogin: String?

    var title: String {
        displayTitle ?? name ?? "Workflow"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayTitle, status, conclusion, event, htmlUrl, headBranch, createdAt, updatedAt
        case repository, actor, triggeringActor
    }

    private struct RepositoryRef: Decodable {
        let fullName: String
    }

    private struct Actor: Decodable {
        let login: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
        event = try container.decodeIfPresent(String.self, forKey: .event)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        headBranch = try container.decodeIfPresent(String.self, forKey: .headBranch)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        repositoryFullName = try container.decode(RepositoryRef.self, forKey: .repository).fullName
        let actor = try container.decodeIfPresent(Actor.self, forKey: .actor)
        let triggeringActor = try container.decodeIfPresent(Actor.self, forKey: .triggeringActor)
        triggeringActorLogin = triggeringActor?.login ?? actor?.login
    }

    init(id: Int, name: String?, displayTitle: String?, status: String?, conclusion: String?,
         event: String? = nil, htmlUrl: String, headBranch: String?, createdAt: Date = Date(), updatedAt: Date,
         repositoryFullName: String, triggeringActorLogin: String? = nil) {
        self.id = id
        self.name = name
        self.displayTitle = displayTitle
        self.status = status
        self.conclusion = conclusion
        self.event = event
        self.htmlUrl = htmlUrl
        self.headBranch = headBranch
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.repositoryFullName = repositoryFullName
        self.triggeringActorLogin = triggeringActorLogin
    }
}

// MARK: - Run Status

enum RunStatus {
    case success
    case failure
    case running
    case queued
    case cancelled
    case unknown

    init(from run: WorkflowRun) {
        switch run.status {
        case "in_progress":
            self = .running
        case "queued", "waiting", "pending", "requested":
            self = .queued
        case "completed":
            switch run.conclusion {
            case "success":
                self = .success
            case "failure", "timed_out", "startup_failure":
                self = .failure
            case "cancelled", "skipped":
                self = .cancelled
            default:
                self = .unknown
            }
        default:
            self = .unknown
        }
    }

    var label: String {
        switch self {
        case .success: return "Success"
        case .failure: return "Failed"
        case .running: return "Running"
        case .queued: return "Queued"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }

    var isActive: Bool {
        self == .running || self == .queued
    }
}

// MARK: - Filtering

enum WorkflowFilterMode: String, CaseIterable {
    case off
    case include
    case exclude
}

extension Array where Element == WorkflowRun {
    /// Keeps or drops runs whose workflow name contains any of the comma-separated patterns (case-insensitive).
    func filtered(by mode: WorkflowFilterMode, patterns: String) -> [WorkflowRun] {
        guard mode != .off else { return self }

        let patterns = patterns
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        guard !patterns.isEmpty else { return self }

        return filter { run in
            let name = (run.name ?? "").lowercased()
            let matches = patterns.contains { name.contains($0) }
            return mode == .include ? matches : !matches
        }
    }

    /// Keeps at most `limit` runs per repository, preserving order.
    func limited(toRunsPerRepo limit: Int) -> [WorkflowRun] {
        var countsByRepo: [String: Int] = [:]
        return filter { run in
            let count = countsByRepo[run.repositoryFullName, default: 0]
            guard count < limit else { return false }
            countsByRepo[run.repositoryFullName] = count + 1
            return true
        }
    }

    /// Running if anything is in flight, otherwise the outcome of the most recently finished run.
    var overallStatus: RunStatus {
        if contains(where: { RunStatus(from: $0).isActive }) {
            return .running
        }

        guard let lastFinishedRun = filter({ $0.status == "completed" })
            .max(by: { $0.updatedAt < $1.updatedAt }) else {
            return .unknown
        }

        return RunStatus(from: lastFinishedRun)
    }
}

// MARK: - Run History

/// The last status seen for each run, to tell which runs finished since the previous fetch.
struct RunHistory {
    private struct Entry {
        let repo: String
        let status: RunStatus
    }

    private var entries: [Int: Entry] = [:] // run.id -> last seen

    /// Runs that have completed since they were last seen queued or in progress.
    func newlyCompleted(in runs: [WorkflowRun]) -> [WorkflowRun] {
        runs.filter { run in
            run.status == "completed" && entries[run.id]?.status.isActive == true
        }
    }

    /// Replaces the history with `runs`. Repos in `failedRepos` weren't loaded this time,
    /// so their runs keep their last status until the repo loads again.
    mutating func record(_ runs: [WorkflowRun], keepingRunsFrom failedRepos: [String]) {
        let failedRepos = Set(failedRepos)
        var newEntries = entries.filter { failedRepos.contains($0.value.repo) }
        for run in runs {
            newEntries[run.id] = Entry(repo: run.repositoryFullName, status: RunStatus(from: run))
        }
        entries = newEntries
    }
}
