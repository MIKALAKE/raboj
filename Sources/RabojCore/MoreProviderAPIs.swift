import Foundation

private func jsonRequest(_ url: URL, method: String = "GET", body: Data? = nil, headers: [String: String]) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    return request
}

private func decodeJSON<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
    do { return try JSONDecoder().decode(type, from: data) } catch { throw APIError.decoding }
}

/// Accepts a JSON number or a numeric string.
struct FlexibleNumber: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { value = number }
        else if let text = try? container.decode(String.self), let number = Double(text) { value = number }
        else { value = 0 }
    }
}

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

// MARK: - xAI

/// xAI Management API: `POST /v1/billing/teams/{team_id}/usage` (daily USD by description).
/// Docs: https://docs.x.ai/developers/rest-api-reference/management/billing
public struct XAIManagementAPI: UsageAPI {
    public init() {}

    static func body(from start: Date, to end: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let object: [String: Any] = [
            "analyticsRequest": [
                "timeRange": ["startTime": formatter.string(from: start), "endTime": formatter.string(from: end), "timezone": "Etc/GMT"],
                "timeUnit": "TIME_UNIT_DAY",
                "values": [["name": "usd", "aggregation": "AGGREGATION_SUM"]],
                "groupBy": ["description"],
                "filters": [String](),
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        guard let team = context.extraID?.trimmingCharacters(in: .whitespaces), !team.isEmpty,
              let encoded = team.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://management-api.x.ai/v1/billing/teams/\(encoded)/usage") else {
            throw APIError.http(400, "Add your xAI team ID in Settings.")
        }
        let request = jsonRequest(url, method: "POST", body: Self.body(from: start, to: end), headers: ["Authorization": "Bearer \(context.key)"])
        return APIFetch(events: try Self.decodeUsage(try await context.send(request)))
    }

    private struct Response: Decodable {
        struct Series: Decodable {
            struct Point: Decodable {
                let timestamp: String
                let values: [FlexibleNumber]
            }
            let group: [String]?
            let dataPoints: [Point]
        }
        let timeSeries: [Series]
    }

    static func decodeUsage(_ data: Data) throws -> [UsageEvent] {
        let response = try decodeJSON(Response.self, data)
        var events: [UsageEvent] = []
        for series in response.timeSeries {
            let description = series.group?.first ?? "xAI"
            let model = description.hasPrefix("Chat ") ? String(description.dropFirst(5)) : description
            for point in series.dataPoints {
                guard let day = Timestamps.parse(point.timestamp), let usd = point.values.first?.value, usd > 0 else { continue }
                events.append(UsageEvent(key: "xa|\(point.timestamp)|\(description)", timestamp: day, model: model, tokens: .zero, costUSD: usd))
            }
        }
        return events
    }
}

// MARK: - GitHub Copilot

/// GitHub REST: `GET /user` then `GET /users/{username}/settings/billing/premium_request/usage?year&month&day`.
/// Works for Copilot plans billed to the user's own account (token permission "Plan": read).
/// Docs: https://docs.github.com/en/rest/billing/usage
public struct CopilotBillingAPI: UsageAPI {
    public init() {}

    private static func headers(_ key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10"]
    }

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        struct User: Decodable { let login: String }
        let userData = try await context.send(jsonRequest(URL(string: "https://api.github.com/user")!, headers: Self.headers(context.key)))
        let login = try decodeJSON(User.self, userData).login
        guard let encoded = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw APIError.decoding }

        let calendar = utcCalendar
        var events: [UsageEvent] = []
        var day = calendar.startOfDay(for: start)
        var requestsLeft = 40 // at most ~40 daily reports per refresh; later refreshes only ask for recent days
        while day < end, requestsLeft > 0 {
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            var components = URLComponents(string: "https://api.github.com/users/\(encoded)/settings/billing/premium_request/usage")!
            components.queryItems = [
                URLQueryItem(name: "year", value: "\(parts.year!)"),
                URLQueryItem(name: "month", value: "\(parts.month!)"),
                URLQueryItem(name: "day", value: "\(parts.day!)"),
            ]
            let data = try await context.send(jsonRequest(components.url!, headers: Self.headers(context.key)))
            events += try Self.decodeDay(data, day: day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
            requestsLeft -= 1
        }

        var monthComponents = URLComponents(string: "https://api.github.com/users/\(encoded)/settings/billing/premium_request/usage")!
        let now = calendar.dateComponents([.year, .month], from: end)
        monthComponents.queryItems = [URLQueryItem(name: "year", value: "\(now.year!)"), URLQueryItem(name: "month", value: "\(now.month!)")]
        let monthData = try await context.send(jsonRequest(monthComponents.url!, headers: Self.headers(context.key)))
        let month = try Self.decodeDay(monthData, day: end)
        let requests = month.reduce(0) { $0 + $1.requests }
        let cost = month.reduce(0) { $0 + ($1.costUSD ?? 0) }
        return APIFetch(events: events, info: [
            InfoItem(title: "Premium requests this month", value: "\(requests)", detail: "billed beyond your plan: \(Format.usd(cost))"),
        ])
    }

    private struct Report: Decodable {
        struct Item: Decodable {
            let model: String?
            let grossQuantity: FlexibleNumber?
            let netAmount: FlexibleNumber?
        }
        let usageItems: [Item]
    }

    static func decodeDay(_ data: Data, day: Date) throws -> [UsageEvent] {
        let report = try decodeJSON(Report.self, data)
        var byModel: [String: (requests: Double, cost: Double)] = [:]
        for item in report.usageItems {
            let model = item.model ?? "Copilot"
            byModel[model, default: (0, 0)].requests += item.grossQuantity?.value ?? 0
            byModel[model, default: (0, 0)].cost += item.netAmount?.value ?? 0
        }
        let dayKey = Int(day.timeIntervalSince1970)
        return byModel.map { model, value in
            UsageEvent(key: "gh|\(dayKey)|\(model)", timestamp: day, model: model, tokens: .zero, costUSD: value.cost, requests: Int(value.requests.rounded()))
        }
    }
}

// MARK: - Cursor

/// Cursor Admin API (teams): `POST /teams/daily-usage-data` and `POST /teams/spend`, Basic auth with the key as user.
/// Docs: https://cursor.com/docs/account/teams/admin-api
public struct CursorAdminAPI: UsageAPI {
    public init() {}

    private func request(_ path: String, key: String, body: [String: Any]) -> URLRequest {
        let auth = Data("\(key):".utf8).base64EncodedString()
        let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return jsonRequest(URL(string: "https://api.cursor.com\(path)")!, method: "POST", body: data, headers: ["Authorization": "Basic \(auth)"])
    }

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        var events: [UsageEvent] = []
        // The endpoint accepts at most 30 days per call.
        var chunkStart = start
        while chunkStart < end {
            let chunkEnd = min(end, chunkStart.addingTimeInterval(30 * 86_400))
            let body: [String: Any] = ["startDate": Int(chunkStart.timeIntervalSince1970 * 1000), "endDate": Int(chunkEnd.timeIntervalSince1970 * 1000)]
            events += try Self.decodeDaily(try await context.send(request("/teams/daily-usage-data", key: context.key, body: body)))
            chunkStart = chunkEnd
        }
        var spendCents = 0.0
        var cycleStart: Date?
        var page = 1
        while page <= maxPages {
            let data = try await context.send(request("/teams/spend", key: context.key, body: ["page": page, "pageSize": 100]))
            let spend = try Self.decodeSpend(data)
            spendCents += spend.cents
            cycleStart = spend.cycleStart
            if page >= spend.totalPages { break }
            page += 1
        }
        let since = cycleStart.map { "since \($0.formatted(date: .abbreviated, time: .omitted))" }
        return APIFetch(events: events, info: [InfoItem(title: "Team on-demand spend this cycle", value: Format.usd(spendCents / 100), detail: since)])
    }

    private struct Daily: Decodable {
        struct Row: Decodable {
            let userId: FlexibleNumber?
            let email: String?
            let date: Double?
            let composerRequests: Int?
            let chatRequests: Int?
            let agentRequests: Int?
            let cmdkUsages: Int?
            let mostUsedModel: String?
        }
        let data: [Row]
    }

    static func decodeDaily(_ data: Data) throws -> [UsageEvent] {
        try decodeJSON(Daily.self, data).data.compactMap { row in
            guard let date = row.date else { return nil }
            let requests = (row.composerRequests ?? 0) + (row.chatRequests ?? 0) + (row.agentRequests ?? 0) + (row.cmdkUsages ?? 0)
            guard requests > 0 else { return nil }
            let user = row.userId.map { String(Int($0.value)) } ?? row.email ?? "?"
            return UsageEvent(key: "cu|\(Int(date))|\(user)", timestamp: Date(timeIntervalSince1970: date / 1000), model: row.mostUsedModel ?? "Cursor", tokens: .zero, requests: requests)
        }
    }

    private struct Spend: Decodable {
        struct Member: Decodable { let spendCents: FlexibleNumber? }
        let teamMemberSpend: [Member]
        let subscriptionCycleStart: Double?
        let totalPages: Int?
    }

    static func decodeSpend(_ data: Data) throws -> (cents: Double, cycleStart: Date?, totalPages: Int) {
        let spend = try decodeJSON(Spend.self, data)
        return (
            spend.teamMemberSpend.reduce(0) { $0 + ($1.spendCents?.value ?? 0) },
            spend.subscriptionCycleStart.map { Date(timeIntervalSince1970: $0 / 1000) },
            spend.totalPages ?? 1
        )
    }
}

// MARK: - OpenRouter

/// OpenRouter: `GET /api/v1/key` reports the key's spend today, this week, this month and its limit.
/// Docs: https://openrouter.ai/docs/api_reference/limits
public struct OpenRouterKeyAPI: UsageAPI {
    public init() {}

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        let data = try await context.send(jsonRequest(URL(string: "https://openrouter.ai/api/v1/key")!, headers: ["Authorization": "Bearer \(context.key)"]))
        return try Self.decode(data, now: end)
    }

    private struct Response: Decodable {
        struct Key: Decodable {
            let usage: Double?
            let usage_daily: Double?
            let usage_weekly: Double?
            let usage_monthly: Double?
            let limit: Double?
            let limit_remaining: Double?
            let limit_reset: String?
        }
        let data: Key
    }

    /// Today's spend becomes a daily event (history builds up while Răboj runs); the rest is shown as info.
    static func decode(_ data: Data, now: Date) throws -> APIFetch {
        let key = try decodeJSON(Response.self, data).data
        let day = utcCalendar.startOfDay(for: now)
        var fetch = APIFetch()
        if let daily = key.usage_daily {
            fetch.events = [UsageEvent(key: "or|\(Int(day.timeIntervalSince1970))", timestamp: day, model: "OpenRouter", tokens: .zero, costUSD: daily)]
        }
        fetch.info = [
            key.usage_weekly.map { InfoItem(title: "This week (UTC)", value: Format.usd($0)) },
            key.usage_monthly.map { InfoItem(title: "This month (UTC)", value: Format.usd($0)) },
            key.usage.map { InfoItem(title: "All time on this key", value: Format.usd($0)) },
        ].compactMap { $0 }
        if let limit = key.limit, limit > 0, let remaining = key.limit_remaining {
            let used = max(0, limit - remaining)
            fetch.plan = PlanSnapshot(
                windows: [PlanWindow(id: "key_limit", title: "Key limit \(key.limit_reset.map { "(\($0))" } ?? "")", usedPercent: used / limit * 100, resetsAt: nil)],
                capturedAt: now,
                source: "\(Format.usd(remaining)) of \(Format.usd(limit)) left"
            )
        }
        return fetch
    }
}

// MARK: - DeepSeek

/// DeepSeek: `GET /user/balance`.
/// Docs: https://api-docs.deepseek.com/api/get-user-balance/
public struct DeepSeekBalanceAPI: UsageAPI {
    public init() {}

    public func fetch(_ context: APIContext, from start: Date, to end: Date) async throws -> APIFetch {
        let data = try await context.send(jsonRequest(URL(string: "https://api.deepseek.com/user/balance")!, headers: ["Authorization": "Bearer \(context.key)"]))
        return APIFetch(info: try Self.decode(data))
    }

    private struct Response: Decodable {
        struct Balance: Decodable {
            let currency: String
            let total_balance: String
            let granted_balance: String?
            let topped_up_balance: String?
        }
        let is_available: Bool?
        let balance_infos: [Balance]
    }

    static func decode(_ data: Data) throws -> [InfoItem] {
        let response = try decodeJSON(Response.self, data)
        let symbol: (String) -> String = { $0 == "CNY" ? "¥" : ($0 == "USD" ? "$" : "\($0) ") }
        var items = response.balance_infos.map { balance in
            InfoItem(
                title: "Balance (\(balance.currency))",
                value: symbol(balance.currency) + balance.total_balance,
                detail: [balance.topped_up_balance.map { "topped up \(symbol(balance.currency))\($0)" }, balance.granted_balance.map { "granted \(symbol(balance.currency))\($0)" }]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
        if response.is_available == false {
            items.append(InfoItem(title: "Status", value: "Insufficient balance"))
        }
        return items
    }
}
