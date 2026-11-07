import Foundation

/// Reads usage from Claude Code's session logs (`<config dir>/projects/**/*.jsonl`).
///
/// Each assistant response is written as one or more lines that repeat the same
/// `message.id` + `requestId` and the same usage, so events are keyed on that pair.
/// Only `timestamp`, `cwd`, `requestId`, `message.id`, `message.model` and `message.usage`
/// are decoded; message text is never read into a model.
public enum ClaudeCodeLogParser {
    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let usageMarker = Data(#""usage""#.utf8)

    private struct Line: Decodable {
        let type: String?
        let timestamp: String?
        let requestId: String?
        let cwd: String?
        let message: Message?
    }

    private struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let input_tokens: Int?
        let output_tokens: Int?
        let cache_creation_input_tokens: Int?
        let cache_read_input_tokens: Int?
    }

    /// Parses one JSONL line. Returns nil for lines that carry no billable usage.
    public static func parse(line: Data, fallbackProject: String? = nil) -> UsageEvent? {
        // Cheap byte checks first: most lines (user turns, tool results, metadata) are skipped without decoding.
        guard line.range(of: usageMarker) != nil, line.range(of: assistantMarker) != nil else { return nil }
        guard let decoded = try? JSONDecoder().decode(Line.self, from: line),
              decoded.type == "assistant",
              let message = decoded.message,
              let usage = message.usage,
              let messageID = message.id,
              let timestampString = decoded.timestamp,
              let timestamp = Timestamps.parse(timestampString)
        else { return nil }

        let model = message.model ?? "unknown"
        // Synthetic entries are Claude Code's own placeholders, not billed model calls.
        if model == "<synthetic>" { return nil }

        let tokens = TokenCounts(
            input: usage.input_tokens ?? 0,
            output: usage.output_tokens ?? 0,
            cacheWrite: usage.cache_creation_input_tokens ?? 0,
            cacheRead: usage.cache_read_input_tokens ?? 0
        )
        let project = decoded.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallbackProject
        return UsageEvent(
            key: "cc|\(messageID)|\(decoded.requestId ?? "")",
            timestamp: timestamp,
            model: model,
            tokens: tokens,
            project: project
        )
    }

    /// Name of the file Claude Code's status line writes plan limits to, when the user sets it up.
    /// See `ClaudeStatusLineSetup`.
    public static let limitsFileName = "raboj-limits.json"

    /// Parses the status-line snapshot Claude Code hands to a configured status line command
    /// (documented `rate_limits.five_hour` / `rate_limits.seven_day` fields).
    public static func parseLimits(_ data: Data, capturedAt: Date) -> PlanSnapshot? {
        struct Snapshot: Decodable {
            struct Limits: Decodable {
                struct Window: Decodable {
                    let used_percentage: Double?
                    let resets_at: Double?
                }
                let five_hour: Window?
                let seven_day: Window?
            }
            let rate_limits: Limits?
        }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              let limits = snapshot.rate_limits else { return nil }
        var windows: [PlanWindow] = []
        func add(_ window: Snapshot.Limits.Window?, id: String, title: String, length: TimeInterval) {
            guard let window, let used = window.used_percentage else { return }
            windows.append(PlanWindow(id: id, title: title, usedPercent: used, resetsAt: window.resets_at.map { Date(timeIntervalSince1970: $0) }, length: length))
        }
        // Same names Claude Code uses in its /usage screen.
        add(limits.five_hour, id: "five_hour", title: "Current session", length: 5 * 3_600)
        add(limits.seven_day, id: "seven_day", title: "This week", length: 7 * 86_400)
        guard !windows.isEmpty else { return nil }
        return PlanSnapshot(windows: windows, capturedAt: capturedAt, source: "from Claude Code’s status line")
    }
}

/// The one-line status line command users add to Claude Code's settings so Răboj can show plan limits.
/// It stores the JSON Claude Code passes on stdin next to the logs, in the folder the user already shared.
public enum ClaudeStatusLineSetup {
    public static let command = #"f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/raboj-limits.json"; cat > "$f.tmp" && mv "$f.tmp" "$f""#

    /// What `settings.json` in a Claude Code folder says about the status line.
    public enum State: Equatable, Sendable {
        case missingFile
        case notSetUp
        /// Another status line is configured; setting up Răboj replaces it.
        case otherStatusLine(String)
        case setUp
    }

    public static func state(of settings: Data?) -> State {
        guard let settings else { return .missingFile }
        guard let object = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return .notSetUp }
        guard let statusLine = object["statusLine"] as? [String: Any] else { return .notSetUp }
        let existing = statusLine["command"] as? String ?? ""
        return existing.contains(ClaudeCodeLogParser.limitsFileName) ? .setUp : .otherStatusLine(existing)
    }

    /// The whole `settings.json` with Răboj's status line added, keeping every other setting.
    /// Returns nil when the existing file is not a JSON object (then the user should paste the snippet by hand).
    public static func mergedSettings(_ settings: Data?) -> String? {
        var object: [String: Any] = [:]
        if let settings, !settings.isEmpty {
            guard let existing = try? JSONSerialization.jsonObject(with: settings) as? [String: Any] else { return nil }
            object = existing
        }
        object["statusLine"] = ["type": "command", "command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// The `statusLine` block to paste into `settings.json`, JSON-escaped.
    public static var settingsSnippet: String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        "statusLine": {
          "type": "command",
          "command": "\(escaped)"
        }
        """
    }
}
