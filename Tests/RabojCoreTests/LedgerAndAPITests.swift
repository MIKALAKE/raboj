import Foundation
import Testing
@testable import RabojCore

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ string: String) -> Date { Timestamps.parse(string)! }

private func event(_ key: String, _ time: String, tokens: Int, model: String = "claude-opus-5-5", project: String? = nil, cost: Double? = nil) -> UsageEvent {
    UsageEvent(key: key, timestamp: date(time), model: model, tokens: TokenCounts(output: tokens), costUSD: cost, project: project)
}

@Suite struct LedgerTests {
    let now = date("2026-11-07T16:00:00Z")

    @Test func todaySummaryComparesWithSevenDayAverage() {
        var ledger = UsageLedger()
        ledger.merge([
            event("a", "2026-11-07T09:00:00Z", tokens: 300, project: "my-app"),
            event("b", "2026-11-07T10:00:00Z", tokens: 100, model: "claude-sonnet-5-5", project: "website"),
            event("c", "2026-11-03T10:00:00Z", tokens: 700),
            event("old", "2026-10-01T10:00:00Z", tokens: 9_999),
        ])
        let today = ledger.summary(.today, now: now, calendar: utc)
        #expect(today.tokens.total == 400)
        #expect(today.byModel.map(\.name) == ["Opus 5.5", "Sonnet 5.5"])
        #expect(today.byProject.first?.name == "my-app")
        // Previous 7 days hold 700 tokens → average 100/day → today is +300%.
        #expect(today.change == 3)

        #expect(ledger.summary(.week, now: now, calendar: utc).tokens.total == 1_100)
        #expect(ledger.summary(.month, now: now, calendar: utc).tokens.total == 1_100)
    }

    @Test func costSummaryUsesDollars() {
        var ledger = UsageLedger()
        ledger.merge([
            event("u", "2026-11-07T00:00:00Z", tokens: 1_000),
            event("c1", "2026-11-07T00:00:00Z", tokens: 0, model: "cost", cost: 4.10),
            event("c0", "2026-11-06T00:00:00Z", tokens: 0, model: "cost", cost: 2.05),
        ])
        let week = ledger.summary(.week, now: now, calendar: utc)
        #expect(abs((week.cost ?? 0) - 6.15) < 0.0001)
        #expect(week.byModel.map(\.name) == ["Opus 5.5"])
    }

    @Test func dailyTotalsCoverEachDay() {
        var ledger = UsageLedger()
        ledger.merge([event("a", "2026-11-07T01:00:00Z", tokens: 5), event("b", "2026-11-05T23:59:00Z", tokens: 7)])
        let days = ledger.daily(days: 7, now: now, calendar: utc)
        #expect(days.count == 7)
        #expect(days.last?.tokens == 5)
        #expect(days[4].tokens == 7)
        #expect(days.first?.day == date("2026-11-01T00:00:00Z"))
    }

    @Test func fiveHourWindowStartsOnTheHourOfTheFirstMessage() throws {
        var ledger = UsageLedger()
        ledger.merge([
            event("a", "2026-11-07T08:10:00Z", tokens: 1), // window 08:00–13:00, over by 16:00
            event("b", "2026-11-07T14:20:00Z", tokens: 2), // new window 14:00–19:00
            event("c", "2026-11-07T15:50:00Z", tokens: 3),
        ])
        let window = try #require(ledger.currentWindow(now: now, calendar: utc))
        #expect(window.start == date("2026-11-07T14:00:00Z"))
        #expect(window.end == date("2026-11-07T19:00:00Z"))
        #expect(window.tokens == 5)
        #expect(ledger.currentWindow(now: date("2026-11-07T19:30:00Z"), calendar: utc) == nil)
    }

    @Test func newerPlanSnapshotWins() {
        var ledger = UsageLedger()
        let older = PlanSnapshot(windows: [PlanWindow(id: "p", title: "x", usedPercent: 10, resetsAt: nil)], capturedAt: date("2026-11-07T10:00:00Z"), source: "")
        let newer = PlanSnapshot(windows: [PlanWindow(id: "p", title: "x", usedPercent: 20, resetsAt: nil)], capturedAt: date("2026-11-07T11:00:00Z"), source: "")
        ledger.offer(plan: newer)
        ledger.offer(plan: older)
        #expect(ledger.plan?.windows.first?.usedPercent == 20)
    }

    @Test func prettyModelNames() {
        #expect(UsageLedger.prettyModel("claude-opus-5-5") == "Opus 5.5")
        #expect(UsageLedger.prettyModel("claude-haiku-5-5-20261001") == "Haiku 5.5")
        #expect(UsageLedger.prettyModel("gpt-x") == "gpt-x")
    }
}

@Suite struct FormatTests {
    @Test func compactTokens() {
        #expect(Format.tokens(980) == "980")
        #expect(Format.tokens(12_345) == "12.3K")
        #expect(Format.tokens(640_000) == "640K")
        #expect(Format.tokens(2_410_000) == "2.41M")
        #expect(Format.tokens(1_000_000) == "1M")
    }

    @Test func otherFormats() {
        #expect(Format.usd(4.1) == "$4.10")
        #expect(Format.change(0.34) == "+34%")
        #expect(Format.change(-0.05) == "−5%")
        let now = Date(timeIntervalSince1970: 0)
        #expect(Format.countdown(to: now.addingTimeInterval(2 * 86_400 + 4 * 3_600 + 60), now: now) == "2d 4h")
        #expect(Format.countdown(to: now.addingTimeInterval(3 * 3_600 + 5 * 60), now: now) == "3h 05m")
    }
}

private struct StubTransport: HTTPTransport {
    let responses: [String: String]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url!.path
        let body = responses.first { path.hasSuffix($0.key) }?.value ?? "{}"
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private final class LogBox: @unchecked Sendable {
    var entries: [AccessLogEntry] = []
}

@Suite struct APITests {
    @Test func anthropicUsageAndCost() async throws {
        let usage = #"{"data":[{"starting_at":"2026-11-06T00:00:00Z","ending_at":"2026-11-07T00:00:00Z","results":[{"uncached_input_tokens":1500,"cache_creation":{"ephemeral_1h_input_tokens":10,"ephemeral_5m_input_tokens":5},"cache_read_input_tokens":200,"output_tokens":500,"model":"claude-opus-5-5"}]}],"has_more":false,"next_page":null}"#
        let cost = #"{"data":[{"starting_at":"2026-11-06T00:00:00Z","ending_at":"2026-11-07T00:00:00Z","results":[{"amount":"123.45","currency":"USD"},{"amount":"76.55","currency":"USD"}]}],"has_more":false,"next_page":null}"#
        let client = GuardedClient(provider: .anthropicAPI, transport: StubTransport(responses: ["usage_report/messages": usage, "cost_report": cost]))
        let log = LogBox()
        let events = try await AnthropicAdminAPI().fetch(key: "sk-ant-admin01-test", from: date("2026-11-01T00:00:00Z"), to: date("2026-11-07T00:00:00Z"), client: client, accountLabel: "Team", log: { log.entries.append($0) })
        let tokens = try #require(events.first { $0.model == "claude-opus-5-5" })
        #expect(tokens.tokens == TokenCounts(input: 1500, output: 500, cacheWrite: 15, cacheRead: 200))
        let money = try #require(events.first { $0.costUSD != nil })
        #expect(abs((money.costUSD ?? 0) - 2.0) < 0.0001)
        #expect(log.entries.map(\.path) == ["/v1/organizations/usage_report/messages", "/v1/organizations/cost_report"])
        #expect(log.entries.allSatisfy { $0.host == "api.anthropic.com" && $0.outcome == "200" })
    }

    @Test func anthropicRequestCarriesKeyOnlyInHeader() {
        let request = AnthropicAdminAPI().request(path: "cost_report", key: "secret", query: [URLQueryItem(name: "limit", value: "1")])
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(!(request.url!.absoluteString.contains("secret")))
    }

    @Test func openAIUsageAndCost() async throws {
        let usage = #"{"object":"page","data":[{"object":"bucket","start_time":1762387200,"end_time":1762473600,"results":[{"object":"organization.usage.completions.result","input_tokens":1000,"input_cached_tokens":400,"output_tokens":50,"model":"gpt-x"}]}],"has_more":false,"next_page":null}"#
        let cost = #"{"object":"page","data":[{"object":"bucket","start_time":1762387200,"end_time":1762473600,"results":[{"object":"organization.costs.result","amount":{"value":1.25,"currency":"usd"}}]}],"has_more":false,"next_page":null}"#
        let client = GuardedClient(provider: .openAIAPI, transport: StubTransport(responses: ["usage/completions": usage, "costs": cost]))
        let events = try await OpenAIAdminAPI().fetch(key: "k", from: Date(timeIntervalSince1970: 1_762_000_000), to: Date(timeIntervalSince1970: 1_762_500_000), client: client, accountLabel: "Org", log: { _ in })
        #expect(events.first { $0.model == "gpt-x" }?.tokens == TokenCounts(input: 600, output: 50, cacheRead: 400))
        #expect(events.first { $0.costUSD != nil }?.costUSD == 1.25)
    }

    @Test func requestsToOtherHostsAreBlocked() async {
        let client = GuardedClient(provider: .anthropicAPI, transport: StubTransport(responses: [:]))
        let log = LogBox()
        await #expect(throws: APIError.hostNotAllowed("evil.example.com")) {
            _ = try await client.get(URLRequest(url: URL(string: "https://evil.example.com/v1/x")!), log: { log.entries.append($0) }, accountLabel: "Team")
        }
        #expect(log.entries.first?.outcome == "blocked")
    }

    @Test func localProvidersMayNotUseTheNetwork() {
        #expect(Provider.claudeCode.allowedHosts.isEmpty)
        #expect(Provider.codex.allowedHosts.isEmpty)
    }
}
