import Foundation

/// Token counts split the way providers bill them.
public struct TokenCounts: Codable, Hashable, Sendable {
    /// Input tokens that were not read from a cache.
    public var input: Int
    public var output: Int
    public var cacheWrite: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
    }

    public static let zero = TokenCounts()

    public var total: Int { input + output + cacheWrite + cacheRead }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) { lhs = lhs + rhs }
}

/// One unit of usage: a model response from a log, or a daily bucket from a provider API.
public struct UsageEvent: Hashable, Sendable {
    /// Stable identity used to drop duplicates; a later event with the same key replaces the earlier one.
    public var key: String
    public var timestamp: Date
    public var model: String
    public var tokens: TokenCounts
    /// Billed cost in USD, when the source reports it.
    public var costUSD: Double?
    /// Project or folder name, when the source reports it.
    public var project: String?
    /// Requests counted by the provider (e.g. Copilot premium requests), when it counts requests instead of tokens.
    public var requests: Int

    public init(key: String, timestamp: Date, model: String, tokens: TokenCounts, costUSD: Double? = nil, project: String? = nil, requests: Int = 0) {
        self.key = key
        self.timestamp = timestamp
        self.model = model
        self.tokens = tokens
        self.costUSD = costUSD
        self.project = project
        self.requests = requests
    }
}

/// A labeled value a provider reports that is not a time series, e.g. an account balance or a key limit.
public struct InfoItem: Hashable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var value: String
    public var detail: String?

    public init(title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }
}

/// One plan-limit window reported by the provider (e.g. Claude's 5-hour window, Codex's weekly limit).
public struct PlanWindow: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// 0–100, may exceed 100 when the limit is passed.
    public var usedPercent: Double
    public var resetsAt: Date?
    /// Length of the window, when known (5 hours, 7 days…). Needed to estimate the pace.
    public var length: TimeInterval?

    public init(id: String, title: String, usedPercent: Double, resetsAt: Date?, length: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.length = length
    }

    /// Where usage is heading if it continues at the same rate until the window resets.
    public enum Pace: Hashable, Sendable {
        /// Expected to end the window at this percent (below 100).
        case onTrack(projectedPercent: Double)
        /// Expected to reach 100% at this moment, before the reset.
        case willHitLimit(at: Date)
        /// Already at or over the limit.
        case limitReached
    }

    /// Linear projection from the share of the window already elapsed. Nil when too early to tell.
    public func pace(now: Date) -> Pace? {
        if usedPercent >= 100 { return .limitReached }
        guard let resetsAt, let length, length > 0 else { return nil }
        let start = resetsAt.addingTimeInterval(-length)
        let elapsed = now.timeIntervalSince(start)
        // Early in a window a single burst says little about the pace.
        guard elapsed >= length * 0.05, elapsed < length, usedPercent > 0 else { return usedPercent == 0 ? .onTrack(projectedPercent: 0) : nil }
        let rate = usedPercent / elapsed
        let projected = usedPercent + rate * resetsAt.timeIntervalSince(now)
        if projected < 100 { return .onTrack(projectedPercent: projected) }
        return .willHitLimit(at: now.addingTimeInterval((100 - usedPercent) / rate))
    }
}

/// The latest plan-limit state known for an account.
public struct PlanSnapshot: Hashable, Sendable {
    public var windows: [PlanWindow]
    public var capturedAt: Date
    /// Where the numbers came from, shown to the user (e.g. "from Codex's own logs").
    public var source: String

    public init(windows: [PlanWindow], capturedAt: Date, source: String) {
        self.windows = windows
        self.capturedAt = capturedAt
        self.source = source
    }

    /// Windows that have not reset yet; a window past its reset time no longer describes the present.
    public func activeWindows(now: Date) -> [PlanWindow] {
        windows.filter { window in
            guard let resetsAt = window.resetsAt else { return true }
            return resetsAt > now
        }
    }

    /// Human title for a window length in minutes.
    public static func title(forWindowMinutes minutes: Int) -> String {
        switch minutes {
        case 300: "5-hour limit"
        case 10_080: "Weekly limit"
        case 43_200: "30-day limit"
        default:
            if minutes % 1_440 == 0 { "\(minutes / 1_440)-day limit" }
            else if minutes % 60 == 0 { "\(minutes / 60)-hour limit" }
            else { "\(minutes)-minute limit" }
        }
    }
}

enum Timestamps {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()

    static func parse(_ string: String) -> Date? {
        (try? fractional.parse(string)) ?? (try? plain.parse(string))
    }
}

extension Data {
    /// Calls `body` for every complete, non-empty line. Bytes after the last newline are not passed.
    /// Returns how many bytes were consumed (up to and including the last newline).
    @discardableResult
    public func forEachCompleteLine(_ body: (Data) -> Void) -> Int {
        var start = startIndex
        var consumedEnd = startIndex
        while let newline = self[start...].firstIndex(of: 0x0A) {
            if newline > start { body(self[start..<newline]) }
            start = index(after: newline)
            consumedEnd = start
        }
        return distance(from: startIndex, to: consumedEnd)
    }
}
