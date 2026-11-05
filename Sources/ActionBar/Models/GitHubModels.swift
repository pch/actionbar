import Foundation

// Responses from the GitHub REST API and OAuth device flow.
// Decoded with `.convertFromSnakeCase`, so property names mirror the JSON keys.

extension JSONDecoder {
    /// A decoder for GitHub REST API responses.
    static func gitHubAPI() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum GitHubAPIError: Error, LocalizedError {
    case invalidToken
    case rateLimited
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid or expired token"
        case .rateLimited:
            return "GitHub API rate limit reached. Please wait and try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "GitHub API returned status \(code)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

/// Recent runs across repositories, plus the repositories whose runs couldn't be loaded.
struct RecentRuns {
    let runs: [WorkflowRun]
    let failedRepos: [String]
}

extension GitHubAPIError {
    /// The error that should fail a fetch across several repos, or nil to return partial results.
    /// An invalid token or a rate limit on any repo fails the fetch, and so does every repo failing.
    /// A repo that loaded with no runs (or with Actions disabled) still counts as loaded.
    static func failingWholeFetch(_ errors: [Error], requestedRepoCount: Int) -> Error? {
        if errors.contains(where: { if case GitHubAPIError.invalidToken = $0 { true } else { false } }) {
            return GitHubAPIError.invalidToken
        }
        if errors.contains(where: { if case GitHubAPIError.rateLimited = $0 { true } else { false } }) {
            return GitHubAPIError.rateLimited
        }
        if let firstError = errors.first, errors.count >= requestedRepoCount {
            return firstError
        }
        return nil
    }
}


struct GitHubUser: Decodable {
    let login: String
}

struct Repository: Decodable, Hashable, Identifiable {
    let id: Int
    let fullName: String
}

struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]
}

// MARK: - GitHub App Installations

/// A response from a paginated list endpoint that reports the total item count.
protocol PaginatedResponse: Decodable {
    associatedtype Item
    var totalCount: Int { get }
    var items: [Item] { get }
}

struct AppInstallation: Decodable {
    let id: Int
}

struct InstallationsResponse: PaginatedResponse {
    let totalCount: Int
    let installations: [AppInstallation]

    var items: [AppInstallation] { installations }
}

struct InstallationRepositoriesResponse: PaginatedResponse {
    let totalCount: Int
    let repositories: [Repository]

    var items: [Repository] { repositories }
}

// MARK: - OAuth Device Flow

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let interval: Int
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?
}
