import Foundation

public enum Period: String, CaseIterable, Codable, Sendable {
    case today, week, month

    public var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }

    var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }
}

public struct NamedShare: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var value: Double
    public var share: Double
}

public struct UsageSummary: Sendable {
    public var tokens: TokenCounts
    public var requests: Int
    /// Billed cost, if any event in the period carried one.
    public var cost: Double?
    /// Relative change versus the comparison baseline (e.g. +0.34 = +34%), nil when there is no baseline.
    public var change: Double?
    /// What `change` compares against, e.g. "7-day avg".
    public var changeBaseline: String
    public var byModel: [NamedShare]
    public var byProject: [NamedShare]
}

public struct DayTotal: Hashable, Sendable, Identifiable {
    public var id: Date { day }
    public var day: Date
    public var tokens: Int
    public var cost: Double
    public var requests: Int
}

/// Claude's usage window: starts at the first message (rounded down to the hour) and lasts five hours.
/// This is an estimate from local activity; real limits come from the provider when available.
public struct WindowEstimate: Hashable, Sendable {
    public var start: Date
    public var end: Date
    public var tokens: Int
    public func elapsedFraction(now: Date) -> Double {
        min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
}

/// All usage known for one account, deduplicated by event key.
public struct UsageLedger: Sendable {
    public private(set) var events: [String: UsageEvent] = [:]
    public var plan: PlanSnapshot?
    /// Latest non-time-series values (balances, limits), replaced on every successful fetch.
    public var info: [InfoItem] = []

    public init() {}

    public mutating func merge(_ newEvents: [UsageEvent]) {
        for event in newEvents { events[event.key] = event }
    }

    public mutating func removeAll() { events.removeAll(); plan = nil; info = [] }

    public mutating func prune(before date: Date) {
        events = events.filter { $0.value.timestamp >= date }
    }

    /// Replace the plan snapshot only with a newer one.
    public mutating func offer(plan newPlan: PlanSnapshot?) {
        guard let newPlan else { return }
        if let plan, plan.capturedAt > newPlan.capturedAt { return }
        plan = newPlan
    }

    public var isEmpty: Bool { events.isEmpty }

    private func events(from start: Date, to end: Date) -> [UsageEvent] {
        events.values.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    public func summary(_ period: Period, now: Date, calendar: Calendar = .current) -> UsageSummary {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: today)!
        let end = now.addingTimeInterval(1)
        let current = events(from: start, to: end)

        var tokens = TokenCounts.zero
        var requests = 0
        var cost = 0.0
        var hasCost = false
        var models: [String: Double] = [:]
        var projects: [String: Double] = [:]
        for event in current {
            tokens += event.tokens
            requests += event.requests
            if let c = event.costUSD { cost += c; hasCost = true }
            // Shares use tokens when there are any, else requests, else cost.
            let weight = event.tokens.total > 0 ? Double(event.tokens.total) : (event.requests > 0 ? Double(event.requests) : (event.costUSD ?? 0))
            if weight > 0, event.model != "cost" { models[Self.prettyModel(event.model), default: 0] += weight }
            if let project = event.project, weight > 0 { projects[project, default: 0] += weight }
        }

        // Baseline: today vs average of the previous 7 full days; 7 and 30 days vs the same length before.
        let metric: (UsageEvent) -> Double
        let currentValue: Double
        if hasCost {
            metric = { $0.costUSD ?? 0 }; currentValue = cost
        } else if tokens.total == 0, requests > 0 {
            metric = { Double($0.requests) }; currentValue = Double(requests)
        } else {
            metric = { Double($0.tokens.total) }; currentValue = Double(tokens.total)
        }
        let baselineDays = period == .today ? 7 : period.days
        let baselineStart = calendar.date(byAdding: .day, value: -baselineDays, to: start)!
        let baselineEvents = events(from: baselineStart, to: start)
        let baselineTotal = baselineEvents.reduce(0) { $0 + metric($1) }
        let baselineValue = period == .today ? baselineTotal / 7 : baselineTotal
        let change: Double? = baselineEvents.isEmpty || baselineValue == 0 ? nil : currentValue / baselineValue - 1
        let baselineLabel: String = switch period {
        case .today: "7-day avg"
        case .week: "previous 7 days"
        case .month: "previous 30 days"
        }

        return UsageSummary(
            tokens: tokens,
            requests: requests,
            cost: hasCost ? cost : nil,
            change: change,
            changeBaseline: baselineLabel,
            byModel: Self.shares(models),
            byProject: Self.shares(projects)
        )
    }

    public func daily(days: Int, now: Date, calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let slice = events(from: day, to: next)
            return DayTotal(
                day: day,
                tokens: slice.reduce(0) { $0 + $1.tokens.total },
                cost: slice.reduce(0) { $0 + ($1.costUSD ?? 0) },
                requests: slice.reduce(0) { $0 + $1.requests }
            )
        }
    }

    /// The current 5-hour window estimated from local activity, or nil if none is open.
    public func currentWindow(now: Date, length: TimeInterval = 5 * 3600, calendar: Calendar = .current) -> WindowEstimate? {
        let recent = events.values
            .filter { $0.timestamp > now.addingTimeInterval(-2 * length) && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
        var windowStart: Date?
        var windowTokens = 0
        for event in recent {
            if let start = windowStart, event.timestamp < start.addingTimeInterval(length) {
                windowTokens += event.tokens.total
            } else {
                let hour = calendar.dateInterval(of: .hour, for: event.timestamp)?.start ?? event.timestamp
                windowStart = hour
                windowTokens = event.tokens.total
            }
        }
        guard let start = windowStart, now < start.addingTimeInterval(length) else { return nil }
        return WindowEstimate(start: start, end: start.addingTimeInterval(length), tokens: windowTokens)
    }

    static func shares(_ values: [String: Double]) -> [NamedShare] {
        let total = values.values.reduce(0, +)
        guard total > 0 else { return [] }
        return values
            .map { NamedShare(name: $0.key, value: $0.value, share: $0.value / total) }
            .sorted { $0.value > $1.value }
    }

    /// "claude-opus-5-5" → "Opus 5.5"; other names are kept as they are.
    public static func prettyModel(_ model: String) -> String {
        let parts = model.split(separator: "-")
        guard parts.first == "claude", parts.count >= 2 else { return model }
        let family = parts[1].capitalized
        let version = parts.dropFirst(2).prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
        return version.isEmpty ? family : "\(family) \(version.joined(separator: "."))"
    }
}
