import Foundation

/// An AI service whose usage Răboj can read.
/// Every provider here has an official API or local logs; see `sourceDescription` and `docsURL`.
public enum Provider: String, Codable, CaseIterable, Sendable {
    // Local tools: read from the logs they write on this Mac. No network.
    case claudeCode
    case codex
    case geminiCLI
    // Official usage APIs, with a key the user creates for this purpose.
    case anthropicAPI
    case openAIAPI
    case xAI
    case githubCopilot
    case cursorTeam
    case openRouter
    case deepSeek

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .anthropicAPI: "Anthropic API"
        case .openAIAPI: "OpenAI API"
        case .xAI: "xAI API (Grok)"
        case .githubCopilot: "GitHub Copilot"
        case .cursorTeam: "Cursor (Teams)"
        case .openRouter: "OpenRouter"
        case .deepSeek: "DeepSeek API"
        }
    }

    /// Two-letter monogram, used when there is no freely licensed logo.
    public var monogram: String {
        switch self {
        case .claudeCode: "CC"
        case .codex: "CX"
        case .geminiCLI: "GE"
        case .anthropicAPI: "AN"
        case .openAIAPI: "OA"
        case .xAI: "xAI"
        case .githubCopilot: "GH"
        case .cursorTeam: "CU"
        case .openRouter: "OR"
        case .deepSeek: "DS"
        }
    }

    public var connection: ConnectionKind {
        switch self {
        case .claudeCode, .codex, .geminiCLI: .folder
        default: .apiKey
        }
    }

    /// Folder name (in the home directory) the tool uses when nothing overrides it.
    /// Only a suggestion for the folder picker; Răboj never reads it unless the user picks it.
    public var defaultFolderName: String? {
        switch self {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        case .geminiCLI: ".gemini"
        default: nil
        }
    }

    /// Subfolder that holds the logs, inside the tool's data folder.
    public var logsSubfolder: String? {
        switch self {
        case .claudeCode: "projects"
        case .codex: "sessions"
        case .geminiCLI: "tmp"
        default: nil
        }
    }

    /// The only hosts Răboj may contact for this provider. Requests to any other host are refused.
    public var allowedHosts: Set<String> {
        switch self {
        case .claudeCode, .codex, .geminiCLI: []
        case .anthropicAPI: ["api.anthropic.com"]
        case .openAIAPI: ["api.openai.com"]
        case .xAI: ["management-api.x.ai"]
        case .githubCopilot: ["api.github.com"]
        case .cursorTeam: ["api.cursor.com"]
        case .openRouter: ["openrouter.ai"]
        case .deepSeek: ["api.deepseek.com"]
        }
    }

    /// What the account's headline number is.
    public var headline: Headline {
        switch self {
        case .claudeCode, .codex, .geminiCLI: .tokens
        case .anthropicAPI, .openAIAPI, .xAI, .openRouter: .cost
        case .githubCopilot, .cursorTeam: .requests
        case .deepSeek: .balance
        }
    }

    /// Short text shown under the provider in the add-account picker.
    public var sourceDescription: String {
        switch self {
        case .claudeCode: "Choose its folder · tokens, plan limits"
        case .codex: "Choose its folder · tokens, plan limit"
        case .geminiCLI: "Choose its folder · tokens"
        case .anthropicAPI: "Admin API key · billed cost, tokens"
        case .openAIAPI: "Admin API key · billed cost, tokens"
        case .xAI: "Management key · billed cost per model"
        case .githubCopilot: "Fine-grained token · premium requests, cost"
        case .cursorTeam: "Team admin key · requests, on-demand spend"
        case .openRouter: "API key · spend per day, key limit"
        case .deepSeek: "API key · account balance"
        }
    }

    /// Name of the secret the user pastes.
    public var keyName: String {
        switch self {
        case .anthropicAPI, .openAIAPI: "Admin API key"
        case .xAI: "Management key"
        case .githubCopilot: "Fine-grained personal access token"
        case .cursorTeam: "Admin API key"
        case .openRouter, .deepSeek: "API key"
        default: "Key"
        }
    }

    /// Where and how to create the key, shown in the add-account form.
    public var keyHelp: String {
        switch self {
        case .anthropicAPI: "Organization admins create an Admin API key (sk-ant-admin…) in the Claude Console. It is used only to read usage and cost reports."
        case .openAIAPI: "Organization owners create an Admin key in the OpenAI platform settings. It is used only to read usage and costs."
        case .xAI: "Create a management key in the xAI Console › Settings › Management Keys, and copy your team ID from the console. Used only for the billing usage report."
        case .githubCopilot: "Create a fine-grained personal access token on GitHub with the account permission “Plan” set to read-only. Works for Copilot plans you pay for yourself; organization-billed seats are not visible to personal tokens."
        case .cursorTeam: "Team admins create an Admin API key in the Cursor dashboard (Teams). Shows team-wide requests and on-demand spend."
        case .openRouter: "Any OpenRouter API key works. Răboj only calls the endpoint that reports that key’s spend and limit."
        case .deepSeek: "Any DeepSeek API key works. Răboj only calls the balance endpoint."
        default: ""
        }
    }

    /// Extra identifier some providers need next to the key.
    public var extraFieldName: String? {
        self == .xAI ? "Team ID" : nil
    }

    public var docsURL: URL? {
        switch self {
        case .claudeCode: URL(string: "https://code.claude.com/docs/en/statusline")
        case .codex: URL(string: "https://developers.openai.com/codex")
        case .geminiCLI: URL(string: "https://github.com/google-gemini/gemini-cli")
        case .anthropicAPI: URL(string: "https://platform.claude.com/docs/en/manage-claude/usage-cost-api")
        case .openAIAPI: URL(string: "https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage")
        case .xAI: URL(string: "https://docs.x.ai/developers/rest-api-reference/management/billing")
        case .githubCopilot: URL(string: "https://docs.github.com/en/rest/billing/usage")
        case .cursorTeam: URL(string: "https://cursor.com/docs/account/teams/admin-api")
        case .openRouter: URL(string: "https://openrouter.ai/docs/api_reference/limits")
        case .deepSeek: URL(string: "https://api-docs.deepseek.com/api/get-user-balance/")
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
    case requests
    case balance
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
    /// Extra identifier a provider needs (xAI team ID).
    public var extraID: String?
    /// A color picked freely (0xRRGGBB); overrides `color` when set.
    public var customColorHex: UInt32?

    public init(
        id: UUID = UUID(),
        provider: Provider,
        label: String,
        color: AccountColor,
        folderPath: String? = nil,
        folderBookmark: Data? = nil,
        includeInAll: Bool = true,
        pinnedInMenuBar: Bool = false,
        refreshMinutes: Int = 15,
        extraID: String? = nil
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
        self.extraID = extraID
    }
}

/// Preset account colors, ordered so neighbours also differ in lightness (readable for color-blind users).
/// Any other color can be chosen per account with `Account.customColorHex`.
public enum AccountColor: String, Codable, CaseIterable, Sendable {
    case blue, orange, teal, purple, graphite, pink, green, red, amber, indigo, cyan, brown

    /// The next color not used yet by `existing`, cycling when all are taken.
    public static func next(after existing: [AccountColor]) -> AccountColor {
        allCases.first { !existing.contains($0) } ?? allCases[existing.count % allCases.count]
    }
}
