import Foundation

/// Sends HTTP requests. Injected so tests never touch the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return (data, http)
    }
}

public enum APIError: Error, LocalizedError, Equatable {
    case hostNotAllowed(String)
    case invalidResponse
    case unauthorized
    case http(Int, String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .hostNotAllowed(let host): "Blocked a request to \(host): not on this provider’s allowed list."
        case .invalidResponse: "The provider sent an unexpected response."
        case .unauthorized: "The key was rejected. Check that it is an Admin API key and still active."
        case .http(let status, let message): "The provider answered \(status): \(message)"
        case .decoding: "Couldn’t read the provider’s response."
        }
    }
}

/// One line of the access log shown to the user. Never contains keys or query strings.
public struct AccessLogEntry: Hashable, Sendable, Identifiable {
    public let id = UUID()
    public var date: Date
    public var accountLabel: String
    public var host: String
    public var path: String
    public var outcome: String
}

/// Wraps a transport and refuses any request whose host is not allowed for the provider.
public struct GuardedClient: Sendable {
    public let provider: Provider
    let transport: HTTPTransport

    public init(provider: Provider, transport: HTTPTransport) {
        self.provider = provider
        self.transport = transport
    }

    public func get(_ request: URLRequest, log: (AccessLogEntry) -> Void, accountLabel: String) async throws -> Data {
        let host = request.url?.host ?? "?"
        let path = (request.httpMethod == "POST" ? "POST " : "") + (request.url?.path ?? "?")
        guard provider.allowedHosts.contains(host), request.url?.scheme == "https" else {
            log(AccessLogEntry(date: Date(), accountLabel: accountLabel, host: host, path: path, outcome: "blocked"))
            throw APIError.hostNotAllowed(host)
        }
        do {
            let (data, response) = try await transport.send(request)
            log(AccessLogEntry(date: Date(), accountLabel: accountLabel, host: host, path: path, outcome: "\(response.statusCode)"))
            switch response.statusCode {
            case 200..<300: return data
            case 401, 403: throw APIError.unauthorized
            default:
                let message = String(data: data.prefix(200), encoding: .utf8) ?? ""
                throw APIError.http(response.statusCode, message)
            }
        } catch let error as APIError {
            throw error
        } catch {
            log(AccessLogEntry(date: Date(), accountLabel: accountLabel, host: host, path: path, outcome: "failed: \(error.localizedDescription)"))
            throw error
        }
    }
}

/// Everything an API source needs for one fetch.
public struct APIContext: Sendable {
    public var key: String
    /// Extra identifier some providers need (xAI team ID).
    public var extraID: String?
    public var accountLabel: String
    public var client: GuardedClient
    public var log: @Sendable (AccessLogEntry) -> Void

    public init(key: String, extraID: String? = nil, accountLabel: String, client: GuardedClient, log: @escaping @Sendable (AccessLogEntry) -> Void) {
        self.key = key
        self.extraID = extraID
        self.accountLabel = accountLabel
        self.client = client
        self.log = log
    }

    func send(_ request: URLRequest) async throws -> Data {
        try await client.get(request, log: log, accountLabel: accountLabel)
    }
}

/// What one fetch from a provider API returned.
public struct APIFetch: Sendable {
    public var events: [UsageEvent] = []
    public var plan: PlanSnapshot?
    public var info: [InfoItem] = []
    public init(events: [UsageEvent] = [], plan: PlanSnapshot? = nil, info: [InfoItem] = []) {
        self.events = events
        self.plan = plan
        self.info = info
    }
}

/// A provider's official usage API.
public protocol UsageAPI: Sendable {
    /// Fetches usage between `start` and `end`. Sources that only report current values ignore the range.
    func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch
}

public extension Provider {
    var api: UsageAPI? {
        switch self {
        case .anthropicAPI: AnthropicAdminAPI()
        case .openAIAPI: OpenAIAdminAPI()
        case .xAI: XAIManagementAPI()
        case .githubCopilot: CopilotBillingAPI()
        case .cursorTeam: CursorAdminAPI()
        case .openRouter: OpenRouterKeyAPI()
        case .deepSeek: DeepSeekBalanceAPI()
        case .claudeCode, .codex, .geminiCLI: nil
        }
    }
}

public let userAgent = "Raboj/0.1 (+https://github.com/MIKALAKE/raboj)"
let maxPages = 10

// MARK: - Anthropic

/// Anthropic Admin API: `GET /v1/organizations/usage_report/messages` and `/v1/organizations/cost_report`.
/// Docs: https://platform.claude.com/docs/en/manage-claude/usage-cost-api
public struct AnthropicAdminAPI: UsageAPI {
    public init() {}

    static let base = URL(string: "https://api.anthropic.com/v1/organizations/")!

    func request(path: String, key: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func rfc3339(_ date: Date) -> String { date.formatted(.iso8601) }

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        let key = context.key
        var events: [UsageEvent] = []
        var page: String?
        for _ in 0..<maxPages {
            var query = [
                URLQueryItem(name: "starting_at", value: Self.rfc3339(start)),
                URLQueryItem(name: "ending_at", value: Self.rfc3339(end)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "group_by[]", value: "model"),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let data = try await context.send(request(path: "usage_report/messages", key: key, query: query))
            let decoded = try Self.decodeUsage(data)
            events += decoded.events
            guard let next = decoded.nextPage else { break }
            page = next
        }
        page = nil
        for _ in 0..<maxPages {
            var query = [
                URLQueryItem(name: "starting_at", value: Self.rfc3339(start)),
                URLQueryItem(name: "ending_at", value: Self.rfc3339(end)),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let data = try await context.send(request(path: "cost_report", key: key, query: query))
            let decoded = try Self.decodeCost(data)
            events += decoded.events
            guard let next = decoded.nextPage else { break }
            page = next
        }
        return APIFetch(events: events)
    }

    private struct Page<Result: Decodable>: Decodable {
        struct Bucket: Decodable {
            let starting_at: String
            let results: [Result]
        }
        let data: [Bucket]
        let has_more: Bool?
        let next_page: String?
    }

    private struct UsageResult: Decodable {
        struct CacheCreation: Decodable {
            let ephemeral_1h_input_tokens: Int?
            let ephemeral_5m_input_tokens: Int?
        }
        let uncached_input_tokens: Int?
        let cache_creation: CacheCreation?
        let cache_read_input_tokens: Int?
        let output_tokens: Int?
        let model: String?
    }

    private struct CostResult: Decodable {
        let amount: String
        let currency: String?
    }

    static func decodeUsage(_ data: Data) throws -> (events: [UsageEvent], nextPage: String?) {
        guard let page = try? JSONDecoder().decode(Page<UsageResult>.self, from: data) else { throw APIError.decoding }
        var events: [UsageEvent] = []
        for bucket in page.data {
            guard let day = Timestamps.parse(bucket.starting_at) else { continue }
            for result in bucket.results {
                let tokens = TokenCounts(
                    input: result.uncached_input_tokens ?? 0,
                    output: result.output_tokens ?? 0,
                    cacheWrite: (result.cache_creation?.ephemeral_1h_input_tokens ?? 0) + (result.cache_creation?.ephemeral_5m_input_tokens ?? 0),
                    cacheRead: result.cache_read_input_tokens ?? 0
                )
                let model = result.model ?? "unknown"
                events.append(UsageEvent(key: "an|usage|\(bucket.starting_at)|\(model)", timestamp: day, model: model, tokens: tokens))
            }
        }
        return (events, page.has_more == true ? page.next_page : nil)
    }

    /// `amount` is a decimal string in cents ("123.45" = $1.23).
    static func decodeCost(_ data: Data) throws -> (events: [UsageEvent], nextPage: String?) {
        guard let page = try? JSONDecoder().decode(Page<CostResult>.self, from: data) else { throw APIError.decoding }
        var events: [UsageEvent] = []
        for bucket in page.data {
            guard let day = Timestamps.parse(bucket.starting_at) else { continue }
            let cents = bucket.results
                .filter { ($0.currency ?? "USD").uppercased() == "USD" }
                .compactMap { Double($0.amount) }
                .reduce(0, +)
            events.append(UsageEvent(key: "an|cost|\(bucket.starting_at)", timestamp: day, model: "cost", tokens: .zero, costUSD: cents / 100))
        }
        return (events, page.has_more == true ? page.next_page : nil)
    }
}

// MARK: - OpenAI

/// OpenAI Admin API: `GET /v1/organization/usage/completions` and `/v1/organization/costs`.
/// Docs: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage
public struct OpenAIAdminAPI: UsageAPI {
    public init() {}

    static let base = URL(string: "https://api.openai.com/v1/organization/")!

    func request(path: String, key: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        let key = context.key
        let startTime = String(Int(start.timeIntervalSince1970))
        let endTime = String(Int(end.timeIntervalSince1970))
        var events: [UsageEvent] = []
        var page: String?
        for _ in 0..<maxPages {
            var query = [
                URLQueryItem(name: "start_time", value: startTime),
                URLQueryItem(name: "end_time", value: endTime),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "group_by", value: "model"),
                URLQueryItem(name: "limit", value: "31"),
            ]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let data = try await context.send(request(path: "usage/completions", key: key, query: query))
            let decoded = try Self.decodeUsage(data)
            events += decoded.events
            guard let next = decoded.nextPage else { break }
            page = next
        }
        page = nil
        for _ in 0..<maxPages {
            var query = [
                URLQueryItem(name: "start_time", value: startTime),
                URLQueryItem(name: "end_time", value: endTime),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "90"),
            ]
            if let page { query.append(URLQueryItem(name: "page", value: page)) }
            let data = try await context.send(request(path: "costs", key: key, query: query))
            let decoded = try Self.decodeCost(data)
            events += decoded.events
            guard let next = decoded.nextPage else { break }
            page = next
        }
        return APIFetch(events: events)
    }

    private struct Page<Result: Decodable>: Decodable {
        struct Bucket: Decodable {
            let start_time: Double
            let results: [Result]
        }
        let data: [Bucket]
        let has_more: Bool?
        let next_page: String?
    }

    private struct UsageResult: Decodable {
        let input_tokens: Int?
        let input_cached_tokens: Int?
        let output_tokens: Int?
        let model: String?
    }

    private struct CostResult: Decodable {
        struct Amount: Decodable {
            let value: Double?
            let currency: String?
        }
        let amount: Amount?
    }

    /// `input_tokens` includes cached input.
    static func decodeUsage(_ data: Data) throws -> (events: [UsageEvent], nextPage: String?) {
        guard let page = try? JSONDecoder().decode(Page<UsageResult>.self, from: data) else { throw APIError.decoding }
        var events: [UsageEvent] = []
        for bucket in page.data {
            let day = Date(timeIntervalSince1970: bucket.start_time)
            for result in bucket.results {
                let cached = result.input_cached_tokens ?? 0
                let tokens = TokenCounts(input: max(0, (result.input_tokens ?? 0) - cached), output: result.output_tokens ?? 0, cacheRead: cached)
                let model = result.model ?? "unknown"
                events.append(UsageEvent(key: "oa|usage|\(Int(bucket.start_time))|\(model)", timestamp: day, model: model, tokens: tokens))
            }
        }
        return (events, page.has_more == true ? page.next_page : nil)
    }

    /// `amount.value` is in the currency's main unit (dollars for "usd").
    static func decodeCost(_ data: Data) throws -> (events: [UsageEvent], nextPage: String?) {
        guard let page = try? JSONDecoder().decode(Page<CostResult>.self, from: data) else { throw APIError.decoding }
        var events: [UsageEvent] = []
        for bucket in page.data {
            let day = Date(timeIntervalSince1970: bucket.start_time)
            let dollars = bucket.results
                .filter { ($0.amount?.currency ?? "usd").lowercased() == "usd" }
                .compactMap { $0.amount?.value }
                .reduce(0, +)
            events.append(UsageEvent(key: "oa|cost|\(Int(bucket.start_time))", timestamp: day, model: "cost", tokens: .zero, costUSD: dollars))
        }
        return (events, page.has_more == true ? page.next_page : nil)
    }
}
