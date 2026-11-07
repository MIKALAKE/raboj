import Foundation

/// An AI service whose usage Răboj can read.
public enum Provider: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codex
    case anthropicAPI
    case openAIAPI

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .anthropicAPI: "Anthropic API"
        case .openAIAPI: "OpenAI API"
        }
    }

    /// Two-letter monogram used in pickers.
    public var monogram: String {
        switch self {
        case .claudeCode: "CC"
        case .codex: "CX"
        case .anthropicAPI: "AN"
        case .openAIAPI: "OA"
        }
    }

    public var connection: ConnectionKind {
        switch self {
        case .claudeCode, .codex: .folder
        case .anthropicAPI, .openAIAPI: .apiKey
        }
    }

    /// Folder name (in the home directory) the tool uses when nothing overrides it.
    /// Only a suggestion for the folder picker; Răboj never reads it unless the user picks it.
    public var defaultFolderName: String? {
        switch self {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        case .anthropicAPI, .openAIAPI: nil
        }
    }

    /// The only hosts Răboj may contact for this provider. Requests to any other host are refused.
    public var allowedHosts: Set<String> {
        switch self {
        case .claudeCode, .codex: []
        case .anthropicAPI: ["api.anthropic.com"]
        case .openAIAPI: ["api.openai.com"]
        }
    }

    /// What the account's headline number is.
    public var headline: Headline {
        switch self {
        case .claudeCode, .codex: .tokens
        case .anthropicAPI, .openAIAPI: .cost
        }
    }

    /// Short text shown under the provider in the add-account picker.
    public var sourceDescription: String {
        switch self {
        case .claudeCode: "Choose its folder · tokens, plan limits"
        case .codex: "Choose its folder · tokens, plan limit"
        case .anthropicAPI: "Admin API key · billed cost, tokens"
        case .openAIAPI: "Admin API key · billed cost, tokens"
        }
    }
}

public enum ConnectionKind: Sendable {
    case folder
    case apiKey
}

public enum Headline: Sendable {
    case tokens
    case cost
}

/// One account = one provider + one source the user connected (a folder or an API key).
/// Any number of accounts per provider is allowed.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var provider: Provider
    /// User-chosen label, e.g. "Work". Never derived from emails or login data.
    public var label: String
    public var color: AccountColor
    /// Display path of the chosen folder (folder accounts only).
    public var folderPath: String?
    /// Security-scoped bookmark of the chosen folder (folder accounts only).
    public var folderBookmark: Data?
    public var includeInAll: Bool
    public var pinnedInMenuBar: Bool
    /// Minutes between refreshes for API accounts.
    public var refreshMinutes: Int

    public init(
        id: UUID = UUID(),
        provider: Provider,
        label: String,
        color: AccountColor,
        folderPath: String? = nil,
        folderBookmark: Data? = nil,
        includeInAll: Bool = true,
        pinnedInMenuBar: Bool = false,
        refreshMinutes: Int = 15
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.color = color
        self.folderPath = folderPath
        self.folderBookmark = folderBookmark
        self.includeInAll = includeInAll
        self.pinnedInMenuBar = pinnedInMenuBar
        self.refreshMinutes = refreshMinutes
    }
}

/// Account colors, chosen so neighbours also differ in lightness (readable for color-blind users).
public enum AccountColor: String, Codable, CaseIterable, Sendable {
    case blue, orange, teal, purple, graphite, pink

    /// The next color not used yet by `existing`, cycling when all are taken.
    public static func next(after existing: [AccountColor]) -> AccountColor {
        allCases.first { !existing.contains($0) } ?? allCases[existing.count % allCases.count]
    }
}
