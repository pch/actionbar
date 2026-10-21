import Foundation

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

actor GitHubAPIClient {
    /// Upper bound on repositories listed for selection (and polled when nothing is selected).
    static let maxRepositories = 200

    private static let baseURL = "https://api.github.com"
    private static let pageSize = 100
    private static let runsPerRepo = 20
    private static let maxRecentRuns = 50
    private static let maxConcurrentRequests = 4
    /// Automated runs (cron jobs, external dispatches) that aren't worth surfacing.
    private static let excludedEvents: Set<String> = ["schedule", "repository_dispatch"]

    private let session: URLSession
    private let decoder: JSONDecoder
    private var workflowRunsCache: [String: CachedWorkflowRunsResponse] = [:]

    private struct CachedWorkflowRunsResponse {
        let etag: String
        let runs: [WorkflowRun]
    }

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        self.session = URLSession(configuration: config)
        self.decoder = .gitHubAPI()
    }

    func clearConditionalCache() {
        workflowRunsCache.removeAll()
    }

    // MARK: - Token Validation

    func validateToken(_ token: String) async throws -> GitHubUser {
        try await get(GitHubUser.self, path: "/user", token: token)
    }

    // MARK: - Workflow Runs

    func fetchRecentRuns(token: String, actor: String? = nil, repos repoNames: [String]? = nil) async throws -> RecentRuns {
        let repoFullNames: [String]
        if let repoNames {
            repoFullNames = repoNames
        } else {
            repoFullNames = try await fetchAllRepos(token: token).map(\.fullName)
        }

        let (allRuns, errors) = await withTaskGroup(of: (String, Result<[WorkflowRun], Error>).self) { group in
            var pendingRepos = repoFullNames.makeIterator()

            func enqueueNextRepo() {
                guard let repo = pendingRepos.next() else { return }
                group.addTask { (repo, await self.fetchRunsResult(repo: repo, token: token, actor: actor)) }
            }

            for _ in 0..<Self.maxConcurrentRequests {
                enqueueNextRepo()
            }

            var allRuns: [WorkflowRun] = []
            var errors: [(repo: String, error: Error)] = []
            while let (repo, result) = await group.next() {
                switch result {
                case .success(let runs): allRuns.append(contentsOf: runs)
                case .failure(let error): errors.append((repo, error))
                }
                enqueueNextRepo()
            }

            return (allRuns, errors)
        }

        // Partial results are fine unless the failure affects every request.
        if errors.contains(where: { if case GitHubAPIError.invalidToken = $0.error { true } else { false } }) {
            throw GitHubAPIError.invalidToken
        }
        if errors.contains(where: { if case GitHubAPIError.rateLimited = $0.error { true } else { false } }) {
            throw GitHubAPIError.rateLimited
        }
        if let firstError = errors.first, allRuns.isEmpty {
            throw firstError.error
        }

        let recentRuns = allRuns
            .filter { run in run.event.map { !Self.excludedEvents.contains($0) } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        return RecentRuns(
            runs: Array(recentRuns.prefix(Self.maxRecentRuns)),
            failedRepos: errors.map(\.repo).sorted()
        )
    }

    private func fetchRunsResult(repo: String, token: String, actor: String?) async -> Result<[WorkflowRun], Error> {
        do {
            return .success(try await fetchRunsForRepo(repo: repo, token: token, actor: actor))
        } catch {
            return .failure(error)
        }
    }

    private func fetchRunsForRepo(repo: String, token: String, actor: String?) async throws -> [WorkflowRun] {
        var queryItems = [URLQueryItem(name: "per_page", value: "\(Self.runsPerRepo)")]
        if let actor {
            queryItems.append(URLQueryItem(name: "actor", value: actor))
        }

        var request = makeRequest(path: "/repos/\(repo)/actions/runs", queryItems: queryItems, token: token)
        let cacheKey = request.url?.absoluteString

        if let cacheKey, let cached = workflowRunsCache[cacheKey] {
            request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await perform(request)
        let httpResponse = try checkedResponse(response)

        if httpResponse.statusCode == 304, let cacheKey, let cached = workflowRunsCache[cacheKey] {
            return cached.runs
        }

        if httpResponse.statusCode == 404 || httpResponse.statusCode == 409 {
            // Actions disabled or no runs available.
            return []
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        let runsResponse: WorkflowRunsResponse
        do {
            runsResponse = try decoder.decode(WorkflowRunsResponse.self, from: data)
        } catch {
            throw GitHubAPIError.decodingError(error)
        }

        if let cacheKey {
            if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
                workflowRunsCache[cacheKey] = CachedWorkflowRunsResponse(etag: etag, runs: runsResponse.workflowRuns)
            } else {
                workflowRunsCache.removeValue(forKey: cacheKey)
            }
        }
        return runsResponse.workflowRuns
    }

    // MARK: - Installations and Repositories

    func hasInstallations(token: String) async throws -> Bool {
        try await !fetchInstallations(token: token).isEmpty
    }

    func fetchAllRepos(token: String) async throws -> [Repository] {
        let installations = try await fetchInstallations(token: token)
        var allRepos: [Repository] = []

        for installation in installations where allRepos.count < Self.maxRepositories {
            allRepos += try await fetchAllPages(
                InstallationRepositoriesResponse.self,
                path: "/user/installations/\(installation.id)/repositories",
                token: token,
                limit: Self.maxRepositories - allRepos.count
            )
        }

        let sorted = allRepos.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        return Array(sorted.prefix(Self.maxRepositories))
    }

    private func fetchInstallations(token: String) async throws -> [AppInstallation] {
        try await fetchAllPages(InstallationsResponse.self, path: "/user/installations", token: token)
    }

    // MARK: - Requests

    /// Follows `page` numbers until every item (or at least `limit` items) has been fetched.
    private func fetchAllPages<Response: PaginatedResponse>(
        _ type: Response.Type,
        path: String,
        token: String,
        limit: Int = .max
    ) async throws -> [Response.Item] {
        var items: [Response.Item] = []
        var page = 1

        while items.count < limit {
            let response = try await get(
                type,
                path: path,
                queryItems: [
                    URLQueryItem(name: "per_page", value: "\(Self.pageSize)"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ],
                token: token
            )
            items += response.items
            if items.count >= response.totalCount || response.items.count < Self.pageSize { break }
            page += 1
        }

        return items
    }

    private func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String
    ) async throws -> T {
        let request = makeRequest(path: path, queryItems: queryItems, token: token)
        let (data, response) = try await perform(request)
        let httpResponse = try checkedResponse(response)

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GitHubAPIError.decodingError(error)
        }
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], token: String) -> URLRequest {
        var components = URLComponents(string: Self.baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }

    /// Throws for responses that are never usable: non-HTTP, unauthorized, or rate limited.
    private func checkedResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }
        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }
        if isRateLimited(httpResponse) {
            throw GitHubAPIError.rateLimited
        }
        return httpResponse
    }

    private func isRateLimited(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 429
            || (response.statusCode == 403 && response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0")
    }
}
