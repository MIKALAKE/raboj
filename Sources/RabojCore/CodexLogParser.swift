import Foundation

/// Reads usage and plan limits from one Codex session log (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).
///
/// Newer Codex versions write a `token_usage_record` per model response (keyed by `response_id`).
/// Older ones only write cumulative `token_count` events; for those files usage is the difference
/// between consecutive totals. `token_count` events also carry the plan's `rate_limits`.
public final class CodexSessionParser {
    private let fileID: String
    private let usesUsageRecords: Bool
    private var model = "unknown"
    private var project: String?
    private var lastTotal: TokenCounts?
    private var lineNumber = 0

    /// - Parameters:
    ///   - fileID: stable identifier of the file (its path), used in event keys.
    ///   - usesUsageRecords: whether the file contains `token_usage_record` lines (checked on first read).
    public init(fileID: String, usesUsageRecords: Bool) {
        self.fileID = fileID
        self.usesUsageRecords = usesUsageRecords
    }

    public static func fileUsesUsageRecords(_ data: Data) -> Bool {
        data.range(of: Data(#""token_usage_record""#.utf8)) != nil
    }

    public struct Output {
        public var events: [UsageEvent] = []
        public var plan: PlanSnapshot?
    }

    public func consume(line: Data) -> Output {
        lineNumber += 1
        var output = Output()
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String else { return output }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let timestamp = (object["timestamp"] as? String).flatMap(Timestamps.parse)

        switch type {
        case "turn_context":
            if let model = payload["model"] as? String { self.model = model }
            if let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
        case "session_meta":
            if let cwd = payload["cwd"] as? String { project = URL(fileURLWithPath: cwd).lastPathComponent }
        case "token_usage_record":
            guard usesUsageRecords, let timestamp,
                  let usage = payload["usage"] as? [String: Any] else { break }
            let id = payload["response_id"] as? String ?? "\(fileID)#\(lineNumber)"
            output.events.append(UsageEvent(key: "cx|\(id)", timestamp: timestamp, model: model, tokens: Self.tokens(usage), project: project))
        case "event_msg" where payload["type"] as? String == "token_count":
            if let limits = payload["rate_limits"] as? [String: Any], let timestamp {
                output.plan = Self.plan(limits, capturedAt: timestamp)
            }
            guard !usesUsageRecords, let timestamp,
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else { break }
            let current = Self.tokens(total)
            let previous = lastTotal ?? .zero
            lastTotal = current
            let delta = TokenCounts(
                input: max(0, current.input - previous.input),
                output: max(0, current.output - previous.output),
                cacheWrite: max(0, current.cacheWrite - previous.cacheWrite),
                cacheRead: max(0, current.cacheRead - previous.cacheRead)
            )
            if delta.total > 0 {
                output.events.append(UsageEvent(key: "cx|\(fileID)#\(lineNumber)", timestamp: timestamp, model: model, tokens: delta, project: project))
            }
        default:
            break
        }
        return output
    }

    /// Codex reports OpenAI-style usage: `input_tokens` includes the cached part.
    static func tokens(_ usage: [String: Any]) -> TokenCounts {
        func int(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        let cached = int("cached_input_tokens")
        return TokenCounts(
            input: max(0, int("input_tokens") - cached),
            output: int("output_tokens"),
            cacheWrite: int("cache_write_input_tokens"),
            cacheRead: cached
        )
    }

    static func plan(_ limits: [String: Any], capturedAt: Date) -> PlanSnapshot? {
        var windows: [PlanWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = limits[key] as? [String: Any],
                  let used = (window["used_percent"] as? NSNumber)?.doubleValue else { continue }
            let minutes = (window["window_minutes"] as? NSNumber)?.intValue
            let resets = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(PlanWindow(
                id: key,
                title: minutes.map(PlanSnapshot.title(forWindowMinutes:)) ?? "Plan limit",
                usedPercent: used,
                resetsAt: resets,
                length: minutes.map { TimeInterval($0 * 60) }
            ))
        }
        guard !windows.isEmpty else { return nil }
        return PlanSnapshot(windows: windows, capturedAt: capturedAt, source: "from Codex’s own logs")
    }
}
