import Foundation

// MARK: - API Response Models

struct ReposResponse: Decodable {
    // Used for array decoding — GitHub returns [Repository]
}

struct Repository: Decodable, Hashable, Identifiable {
    let id: Int
    let fullName: String
    let htmlUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case htmlUrl = "html_url"
    }

    init(id: Int, fullName: String, htmlUrl: String) {
        self.id = id
        self.fullName = fullName
        self.htmlUrl = htmlUrl
    }
}

struct WorkflowRunsResponse: Decodable {
    let totalCount: Int
    let workflowRuns: [WorkflowRun]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRun: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let status: String?
    let conclusion: String?
    let event: String?
    let htmlUrl: String
    let headBranch: String?
    let updatedAt: Date
    let repositoryFullName: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case displayTitle = "display_title"
        case status
        case conclusion
        case event
        case htmlUrl = "html_url"
        case headBranch = "head_branch"
        case updatedAt = "updated_at"
        case repository
    }

    enum RepositoryCodingKeys: String, CodingKey {
        case fullName = "full_name"
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
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        let repoContainer = try container.nestedContainer(keyedBy: RepositoryCodingKeys.self, forKey: .repository)
        repositoryFullName = try repoContainer.decode(String.self, forKey: .fullName)
    }

    init(id: Int, name: String?, displayTitle: String?, status: String?, conclusion: String?,
         event: String? = nil, htmlUrl: String, headBranch: String?, updatedAt: Date, repositoryFullName: String) {
        self.id = id
        self.name = name
        self.displayTitle = displayTitle
        self.status = status
        self.conclusion = conclusion
        self.event = event
        self.htmlUrl = htmlUrl
        self.headBranch = headBranch
        self.updatedAt = updatedAt
        self.repositoryFullName = repositoryFullName
    }
}

// MARK: - Workflow Filter Mode

enum WorkflowFilterMode: String, CaseIterable {
    case off
    case include
    case exclude
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
}

// MARK: - GitHub App Installation Models

struct InstallationsResponse: Decodable {
    let totalCount: Int
    let installations: [AppInstallation]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case installations
    }
}

struct AppInstallation: Decodable {
    let id: Int
    let account: Account

    struct Account: Decodable {
        let login: String
    }
}

struct InstallationRepositoriesResponse: Decodable {
    let totalCount: Int
    let repositories: [Repository]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
    }
}

// MARK: - GitHub User (for token validation)

struct GitHubUser: Decodable {
    let login: String
    let id: Int
}
