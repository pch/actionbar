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

actor GitHubAPIClient {
    private let baseURL = "https://api.github.com"
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Token Validation

    func validateToken(_ token: String) async throws -> GitHubUser {
        let request = makeRequest(path: "/user", token: token)
        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }

        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }

        if isRateLimited(httpResponse) {
            throw GitHubAPIError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(GitHubUser.self, from: data)
        } catch {
            throw GitHubAPIError.decodingError(error)
        }
    }

    // MARK: - Fetch Workflow Runs

    func fetchRecentRuns(token: String, actor: String? = nil, repos repoNames: [String]? = nil) async throws -> [WorkflowRun] {
        let repoFullNames: [String]
        if let repoNames {
            repoFullNames = repoNames
        } else {
            repoFullNames = try await fetchRepos(token: token).map(\.fullName)
        }

        let (allRuns, errors) = await withTaskGroup(of: (runs: [WorkflowRun], error: Error?).self) { group in
            let maxConcurrentRequests = 4
            var iterator = repoFullNames.makeIterator()

            for _ in 0..<maxConcurrentRequests {
                guard let repoName = iterator.next() else { break }
                group.addTask {
                    do {
                        let runs = try await self.fetchRunsForRepo(repo: repoName, token: token, actor: actor)
                        return (runs: runs, error: nil)
                    } catch {
                        return (runs: [], error: error)
                    }
                }
            }

            var allRuns: [WorkflowRun] = []
            var errors: [Error] = []
            while let result = await group.next() {
                allRuns.append(contentsOf: result.runs)
                if let error = result.error {
                    // Allow partial results unless the failure is critical.
                    errors.append(error)
                }
                if let repoName = iterator.next() {
                    group.addTask {
                        do {
                            let runs = try await self.fetchRunsForRepo(repo: repoName, token: token, actor: actor)
                            return (runs: runs, error: nil)
                        } catch {
                            return (runs: [], error: error)
                        }
                    }
                }
            }

            return (allRuns, errors)
        }

        if errors.contains(where: { error in
            guard let apiError = error as? GitHubAPIError else { return false }
            if case .invalidToken = apiError { return true }
            return false
        }) {
            throw GitHubAPIError.invalidToken
        }
        if errors.contains(where: { error in
            guard let apiError = error as? GitHubAPIError else { return false }
            if case .rateLimited = apiError { return true }
            return false
        }) {
            throw GitHubAPIError.rateLimited
        }
        if !errors.isEmpty && allRuns.isEmpty {
            throw errors[0]
        }

        // Filter out automated/scheduled runs (cron jobs, dependabot, etc.)
        let excludedEvents: Set<String> = ["schedule", "repository_dispatch"]
        let filteredRuns = allRuns.filter { run in
            guard let event = run.event else { return true }
            return !excludedEvents.contains(event)
        }

        let sortedRuns = filteredRuns.sorted { $0.updatedAt > $1.updatedAt }
        return Array(sortedRuns.prefix(50))
    }

    // MARK: - Installations

    func fetchInstallations(token: String) async throws -> [AppInstallation] {
        var allInstallations: [AppInstallation] = []
        var page = 1

        while true {
            let request = makeRequest(
                path: "/user/installations",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ],
                token: token
            )

            let (data, response) = try await perform(request)
            try validateResponse(response)

            let result: InstallationsResponse
            do {
                result = try decoder.decode(InstallationsResponse.self, from: data)
            } catch {
                throw GitHubAPIError.decodingError(error)
            }

            allInstallations.append(contentsOf: result.installations)
            if allInstallations.count >= result.totalCount || result.installations.count < 100 { break }
            page += 1
        }

        return allInstallations
    }

    func hasInstallations(token: String) async throws -> Bool {
        let installations = try await fetchInstallations(token: token)
        return !installations.isEmpty
    }

    func fetchAllRepos(token: String) async throws -> [Repository] {
        let installations = try await fetchInstallations(token: token)
        var allRepos: [Repository] = []
        let maxRepos = 200

        for installation in installations {
            var page = 1
            while allRepos.count < maxRepos {
                let request = makeRequest(
                    path: "/user/installations/\(installation.id)/repositories",
                    queryItems: [
                        URLQueryItem(name: "per_page", value: "100"),
                        URLQueryItem(name: "page", value: "\(page)"),
                    ],
                    token: token
                )

                let (data, response) = try await perform(request)
                try validateResponse(response)

                let result: InstallationRepositoriesResponse
                do {
                    result = try decoder.decode(InstallationRepositoriesResponse.self, from: data)
                } catch {
                    throw GitHubAPIError.decodingError(error)
                }

                allRepos.append(contentsOf: result.repositories)
                if allRepos.count >= result.totalCount || result.repositories.count < 100 { break }
                page += 1
            }

            if allRepos.count >= maxRepos { break }
        }

        let sorted = allRepos.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        return Array(sorted.prefix(maxRepos))
    }

    // MARK: - Private

    private func fetchRepos(token: String) async throws -> [Repository] {
        return try await fetchAllRepos(token: token)
    }

    private func fetchRunsForRepo(repo: String, token: String, actor: String? = nil) async throws -> [WorkflowRun] {
        var queryItems = [URLQueryItem(name: "per_page", value: "10")]
        if let actor {
            queryItems.append(URLQueryItem(name: "actor", value: actor))
        }

        let request = makeRequest(
            path: "/repos/\(repo)/actions/runs",
            queryItems: queryItems,
            token: token
        )

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }

        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }

        if isRateLimited(httpResponse) {
            throw GitHubAPIError.rateLimited
        }

        if httpResponse.statusCode == 404 || httpResponse.statusCode == 409 {
            // Actions disabled or no runs available.
            return []
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            let runsResponse = try decoder.decode(WorkflowRunsResponse.self, from: data)
            return runsResponse.workflowRuns
        } catch {
            return []
        }
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], token: String) -> URLRequest {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }
        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }
        if isRateLimited(httpResponse) {
            throw GitHubAPIError.rateLimited
        }
        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }
    }

    private func isRateLimited(_ response: HTTPURLResponse) -> Bool {
        if response.statusCode == 429 { return true }
        if response.statusCode == 403,
           let remaining = response.value(forHTTPHeaderField: "x-ratelimit-remaining"),
           remaining == "0" {
            return true
        }
        return false
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
}
