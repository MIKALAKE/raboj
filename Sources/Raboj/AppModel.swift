import AppKit
import Combine
import Foundation
import RabojCore
import ServiceManagement

enum Selection: Hashable, Codable {
    case all
    case account(UUID)
}

enum MenuBarMode: String, Codable, CaseIterable, Identifiable {
    case selection, pinned, iconOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .selection: "The account open in the popover"
        case .pinned: "Pinned accounts side by side"
        case .iconOnly: "Icon only"
        }
    }
}

/// What the All view and the menu bar show for each account.
enum AllMetric: String, Codable, CaseIterable, Identifiable {
    case auto, tokens, limits, cost, requests
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Auto"
        case .tokens: "Tokens"
        case .limits: "Limits"
        case .cost: "Cost"
        case .requests: "Requests"
        }
    }
}

/// One account's number for a metric, with how full its bar is and a short explanation.
struct MetricValue {
    var text: String
    var fraction: Double?
    var note: String
}

/// Usage found for a Claude account that no Răboj account is linked to yet
/// (e.g. after `/login` with another account inside an existing Claude Code folder).
struct UnlinkedClaudeAccount {
    var ledger = UsageLedger()
    /// Display paths of the folders it was seen in.
    var folders: Set<String> = []
}

struct AccountStatus {
    var lastUpdated: Date?
    var error: String?
    var loading = false
}

private struct StoredState: Codable {
    var accounts: [Account] = []
    var selection: Selection = .all
    var period: Period = .today
    var menuBarMode: MenuBarMode = .selection
    var allMetric: AllMetric? = .auto
    var ignoredClaudeIDs: Set<String>? = []
}

/// Owns accounts, reads their usage on a schedule and exposes everything the UI shows.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var ledgers: [UUID: UsageLedger] = [:]
    @Published private(set) var statuses: [UUID: AccountStatus] = [:]
    @Published private(set) var accessLog: [AccessLogEntry] = []
    @Published private(set) var now = Date()
    @Published var selection: Selection = .all { didSet { save() } }
    @Published var period: Period = .today { didSet { save() } }
    @Published var menuBarMode: MenuBarMode = .selection { didSet { save() } }
    @Published var allMetric: AllMetric = .auto { didSet { save() } }
    /// Claude accounts seen in a folder that aren't linked to any Răboj account, by `accountUuid`.
    @Published private(set) var unlinkedClaude: [String: UnlinkedClaudeAccount] = [:]
    /// Claude accounts the user chose not to add; their usage is dropped.
    private var ignoredClaudeIDs: Set<String> = []

    private var readers: [UUID: FolderReader] = [:]
    private var lastAPIFetch: [UUID: Date] = [:]
    /// End of the last successful API fetch, so later fetches only ask for recent days.
    private var apiFetchedThrough: [UUID: Date] = [:]
    private var apiTasks: [UUID: Task<Void, Never>] = [:]
    private var timer: Timer?
    private let transport = URLSessionTransport()
    private var loaded = false

    init() { load() }

    /// A model with made-up data and no persistence, used to render README screenshots.
    init(demoAccounts: [Account], ledgers: [UUID: UsageLedger], now: Date) {
        accounts = demoAccounts
        self.ledgers = ledgers
        self.now = now
        for account in demoAccounts { statuses[account.id] = AccountStatus(lastUpdated: now) }
    }

    // MARK: - Lifecycle

    func start() {
        for account in accounts { prepare(account) }
        tick(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(force: false) }
        }
    }

    private func tick(force: Bool) {
        now = Date()
        for account in accounts { refresh(account, force: force) }
    }

    func refreshAll() {
        lastAPIFetch.removeAll()
        tick(force: true)
    }

    private func prepare(_ account: Account) {
        guard account.provider.connection == .folder else { return }
        readers[account.id] = nil
        if let bookmark = account.folderBookmark, let resolved = FolderAccess.resolve(bookmark) {
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            readers[account.id] = FolderReader(provider: account.provider, root: resolved.url, accessing: accessing)
            if resolved.stale, let fresh = try? resolved.url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
                var updated = account
                updated.folderBookmark = fresh
                replace(updated)
            }
        } else if let path = account.folderPath {
            readers[account.id] = FolderReader(provider: account.provider, root: URL(fileURLWithPath: path), accessing: false)
        }
    }

    private func refresh(_ account: Account, force: Bool) {
        switch account.provider.connection {
        case .folder:
            guard let reader = readers[account.id] else {
                if isFolderless(account) {
                    statuses[account.id, default: AccountStatus()].lastUpdated = Date()
                    return
                }
                statuses[account.id, default: AccountStatus()].error = "No access to the folder. Choose it again in Settings."
                return
            }
            if ledgers[account.id] == nil { statuses[account.id, default: AccountStatus()].loading = true }
            let id = account.id
            reader.poll { [weak self] result in
                Task { @MainActor in self?.apply(result, to: id) }
            }
        case .apiKey:
            let interval = TimeInterval(max(5, account.refreshMinutes) * 60)
            if !force, let last = lastAPIFetch[account.id], now.timeIntervalSince(last) < interval { return }
            lastAPIFetch[account.id] = now
            fetchAPI(account)
        }
    }

    private func apply(_ result: ReadResult, to id: UUID) {
        guard let account = account(id) else { return }
        var status = statuses[id] ?? AccountStatus()
        status.loading = false
        status.error = result.error
        if result.error == nil { status.lastUpdated = Date() }
        statuses[id] = status
        if account.provider == .claudeCode {
            routeClaude(result, from: account)
            return
        }
        guard !result.events.isEmpty || result.plan != nil || result.info != nil || ledgers[id] == nil else { return }
        absorb(result.events, plan: result.plan, info: result.info, into: id)
    }

    private func absorb(_ events: [UsageEvent], plan: PlanSnapshot?, info: [InfoItem]? = nil, into id: UUID) {
        var ledger = ledgers[id] ?? UsageLedger()
        ledger.merge(events)
        ledger.offer(plan: plan)
        if let info { ledger.info = info }
        ledger.prune(before: Date().addingTimeInterval(-FolderReader.retention))
        ledgers[id] = ledger
    }

    // MARK: - Claude account identity

    /// Where a Claude Code event or plan snapshot belongs.
    private enum ClaudeDestination: Hashable {
        case account(UUID)
        case unlinked(String)
        case ignored
    }

    /// Files a Claude Code folder's usage under the Răboj account linked to the Claude account that made it,
    /// so a folder logged in to another account partway through doesn't mix the two.
    private func routeClaude(_ result: ReadResult, from source: Account) {
        var source = source
        if source.claudeAccountID == nil, let home = homeClaudeID(in: result.events, excluding: source.id) {
            source.claudeAccountID = home
            replace(source)
            if let pending = unlinkedClaude.removeValue(forKey: home) {
                absorb(Array(pending.ledger.events.values), plan: pending.ledger.plan, into: source.id)
            }
        }
        if ledgers[source.id] == nil { ledgers[source.id] = UsageLedger() }

        var buckets: [ClaudeDestination: [UsageEvent]] = [:]
        for event in result.events { buckets[destination(for: event.ownerID, source: source), default: []].append(event) }
        let planDestination = result.plan.map { destination(for: $0.ownerID, source: source) }
        for target in Set(buckets.keys).union(planDestination.map { [$0] } ?? []) {
            let events = buckets[target] ?? []
            let plan = planDestination == target ? result.plan : nil
            switch target {
            case .account(let id):
                absorb(events, plan: plan, into: id)
            case .unlinked(let owner):
                var pending = unlinkedClaude[owner] ?? UnlinkedClaudeAccount()
                pending.ledger.merge(events)
                pending.ledger.offer(plan: plan)
                pending.ledger.prune(before: Date().addingTimeInterval(-FolderReader.retention))
                if let path = source.folderPath { pending.folders.insert(FolderAccess.displayPath(path)) }
                unlinkedClaude[owner] = pending
            case .ignored:
                break
            }
        }
    }

    private func destination(for owner: String?, source: Account) -> ClaudeDestination {
        guard let owner, owner != source.claudeAccountID else { return .account(source.id) }
        if let linked = accounts.first(where: { $0.provider == .claudeCode && $0.claudeAccountID == owner }) { return .account(linked.id) }
        if source.claudeAccountID == nil { return .account(source.id) }
        if ignoredClaudeIDs.contains(owner) { return .ignored }
        return .unlinked(owner)
    }

    /// The Claude account a folder was set up for: the first one seen in its logs, skipping ones already linked elsewhere.
    /// Not the most used one: a folder logged in to another account for a few busy days can have more of its usage.
    private func homeClaudeID(in events: [UsageEvent], excluding id: UUID) -> String? {
        let taken = Set(accounts.filter { $0.id != id }.compactMap(\.claudeAccountID))
        return events
            .filter { $0.ownerID.map { !taken.contains($0) } ?? false }
            .min { $0.timestamp < $1.timestamp }?
            .ownerID
    }

    /// Adds a Răboj account for a Claude account found in another account's folder.
    /// It needs no folder of its own: its usage comes from whichever folder it was used in.
    func addUnlinkedClaude(_ owner: String) {
        guard let pending = unlinkedClaude.removeValue(forKey: owner) else { return }
        let count = accounts.filter { $0.provider == .claudeCode }.count + 1
        let account = Account(provider: .claudeCode, label: "Claude \(count)", color: nextColor, claudeAccountID: owner)
        accounts.append(account)
        ledgers[account.id] = pending.ledger
        statuses[account.id] = AccountStatus(lastUpdated: Date())
        save()
        selection = .account(account.id)
    }

    /// Stops showing a Claude account found in another account's folder; its usage is ignored from now on.
    func ignoreUnlinkedClaude(_ owner: String) {
        unlinkedClaude[owner] = nil
        ignoredClaudeIDs.insert(owner)
        save()
    }

    /// Reads every Claude Code folder again from the start, after links between folders and accounts changed.
    private func rereadClaudeFolders() {
        unlinkedClaude.removeAll()
        for account in accounts where account.provider == .claudeCode {
            ledgers[account.id] = nil
            prepare(account)
        }
        for account in accounts where account.provider == .claudeCode { refresh(account, force: true) }
    }

    /// True for a Claude account added from another folder: it has no folder of its own.
    func isFolderless(_ account: Account) -> Bool {
        account.provider == .claudeCode && account.claudeAccountID != nil && account.folderBookmark == nil && account.folderPath == nil
    }

    private func fetchAPI(_ account: Account) {
        guard let api = account.provider.api else { return }
        guard let key = Keychain.read(account.id) else {
            statuses[account.id, default: AccountStatus()].error = "No key saved. Add it again in Settings."
            return
        }
        statuses[account.id, default: AccountStatus()].loading = true
        let id = account.id
        let end = Date()
        let retentionStart = Calendar.current.startOfDay(for: end.addingTimeInterval(-FolderReader.retention))
        // After the first full fetch, re-read only the last few days: older days don't change.
        let start = apiFetchedThrough[id].map { max(retentionStart, Calendar.current.startOfDay(for: $0.addingTimeInterval(-2 * 86_400))) } ?? retentionStart
        let context = makeContext(key: key, provider: account.provider, label: account.label, extraID: account.extraID)
        apiTasks[id]?.cancel()
        apiTasks[id] = Task { [weak self] in
            do {
                let fetched = try await api.fetch(context, from: start, to: end)
                self?.apiFetchedThrough[id] = end
                self?.apply(ReadResult(events: fetched.events, plan: fetched.plan, info: fetched.info), to: id)
            } catch is CancellationError {
            } catch {
                self?.apply(ReadResult(error: error.localizedDescription), to: id)
            }
        }
    }

    private func makeContext(key: String, provider: Provider, label: String, extraID: String?) -> APIContext {
        APIContext(key: key, extraID: extraID, accountLabel: label, client: GuardedClient(provider: provider, transport: transport)) { [weak self] entry in
            Task { @MainActor in self?.appendLog(entry) }
        }
    }

    /// Checks a key before the account is added. Returns nil when it works, or the error to show.
    func test(key: String, provider: Provider, label: String, extraID: String?) async -> String? {
        guard let api = provider.api else { return nil }
        let end = Date()
        do {
            _ = try await api.fetch(makeContext(key: key, provider: provider, label: label, extraID: extraID), from: end.addingTimeInterval(-86_400), to: end)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func appendLog(_ entry: AccessLogEntry) {
        accessLog.insert(entry, at: 0)
        if accessLog.count > 300 { accessLog.removeLast(accessLog.count - 300) }
    }

    // MARK: - Accounts

    func account(_ id: UUID) -> Account? { accounts.first { $0.id == id } }

    func ledger(_ id: UUID) -> UsageLedger { ledgers[id] ?? UsageLedger() }

    func status(_ id: UUID) -> AccountStatus { statuses[id] ?? AccountStatus() }

    var nextColor: AccountColor { AccountColor.next(after: accounts.map(\.color)) }

    /// Claude Code's settings.json in the account's folder (readable through the folder grant).
    func settingsFile(for account: Account) -> URL? {
        readers[account.id]?.root.appendingPathComponent("settings.json")
    }

    func add(_ account: Account, apiKey: String?) {
        add([account], apiKey: apiKey)
    }

    /// Adds several accounts at once (e.g. a work and a personal Claude Code folder).
    func add(_ newAccounts: [Account], apiKey: String?) {
        for account in newAccounts {
            if let apiKey { Keychain.save(apiKey, for: account.id) }
            accounts.append(account)
            prepare(account)
            refresh(account, force: true)
        }
        save()
        if newAccounts.count == 1, let account = newAccounts.first { selection = .account(account.id) } else { selection = .all }
    }

    /// Saves edits to an account (label, color, toggles, refresh interval).
    func update(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var account = account
        // The settings form may hold a copy made before the Claude account was detected.
        account.claudeAccountID = accounts[index].claudeAccountID
        let folderChanged = accounts[index].folderBookmark != account.folderBookmark || accounts[index].folderPath != account.folderPath
        let sourceChanged = accounts[index].extraID != account.extraID
        accounts[index] = account
        save()
        if folderChanged, account.provider == .claudeCode {
            accounts[index].claudeAccountID = nil
            save()
            rereadClaudeFolders()
        } else if folderChanged {
            ledgers[account.id] = nil
            prepare(account)
            refresh(account, force: true)
        } else if sourceChanged {
            ledgers[account.id] = nil
            apiFetchedThrough[account.id] = nil
            refresh(account, force: true)
        }
    }

    private func replace(_ account: Account) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        save()
    }

    func replaceKey(_ key: String, for account: Account) {
        Keychain.save(key, for: account.id)
        statuses[account.id]?.error = nil
        apiFetchedThrough[account.id] = nil
        refresh(account, force: true)
    }

    func remove(_ id: UUID) {
        let wasClaude = account(id)?.provider == .claudeCode
        Keychain.delete(id)
        apiTasks[id]?.cancel()
        readers[id] = nil
        ledgers[id] = nil
        statuses[id] = nil
        apiFetchedThrough[id] = nil
        lastAPIFetch[id] = nil
        accounts.removeAll { $0.id == id }
        if selection == .account(id) { selection = .all }
        save()
        // Other folders may hold usage that was filed under the removed account.
        if wasClaude { rereadClaudeFolders() }
    }

    func move(from source: IndexSet, to destination: Int) {
        accounts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Selection

    /// All, then each account in order; ⌘0 … ⌘9 map onto this list.
    var selectionOrder: [Selection] { [.all] + accounts.map { .account($0.id) } }

    func cycleSelection() {
        let order = selectionOrder
        guard let index = order.firstIndex(of: selection) else { selection = .all; return }
        selection = order[(index + 1) % order.count]
    }

    // MARK: - Headline numbers

    /// The single number that best describes an account right now: plan % when known, else today's cost or tokens.
    func headline(_ account: Account) -> String {
        let ledger = ledger(account.id)
        if let window = ledger.plan?.activeWindows(now: now).max(by: { $0.usedPercent < $1.usedPercent }) {
            return Format.percent(window.usedPercent)
        }
        let today = ledger.summary(.today, now: now)
        switch account.provider.headline {
        case .cost: return Format.usd(today.cost ?? 0)
        case .tokens: return Format.tokens(today.tokens.total)
        case .requests: return "\(today.requests) req"
        case .balance: return ledger.info.first?.value ?? "—"
        }
    }

    /// Metrics that make sense for the accounts that exist (Requests only when some provider counts requests).
    var availableMetrics: [AllMetric] {
        AllMetric.allCases.filter { metric in
            metric != .requests || accounts.contains { $0.provider.headline == .requests }
        }
    }

    /// The account's number for a metric; text is "—" when the provider has no such data.
    func value(_ account: Account, metric: AllMetric) -> MetricValue {
        let ledger = ledger(account.id)
        let today = ledger.summary(.today, now: now)
        switch metric {
        case .auto:
            return MetricValue(text: headline(account), fraction: autoFraction(account), note: "")
        case .tokens:
            return today.tokens.total > 0 || account.provider.headline == .tokens
                ? MetricValue(text: Format.tokens(today.tokens.total), fraction: nil, note: "tokens today")
                : MetricValue(text: "—", fraction: nil, note: "\(account.provider.displayName) doesn’t report tokens")
        case .limits:
            if let window = ledger.plan?.activeWindows(now: now).max(by: { $0.usedPercent < $1.usedPercent }) {
                let reset = window.resetsAt.map { " · resets in \(Format.countdown(to: $0, now: now))" } ?? ""
                return MetricValue(text: Format.percent(window.usedPercent), fraction: window.usedPercent / 100, note: window.title + reset)
            }
            let hint = account.provider == .claudeCode ? "Set up limits in Settings › Accounts" : "No plan limits from this provider"
            return MetricValue(text: "—", fraction: nil, note: hint)
        case .cost:
            if let cost = today.cost { return MetricValue(text: Format.usd(cost), fraction: nil, note: "billed today") }
            if account.provider.headline == .balance, let first = ledger.info.first { return MetricValue(text: first.value, fraction: nil, note: first.title) }
            return MetricValue(text: "—", fraction: nil, note: "\(account.provider.displayName) doesn’t report cost")
        case .requests:
            return account.provider.headline == .requests
                ? MetricValue(text: "\(today.requests)", fraction: nil, note: "requests today")
                : MetricValue(text: "—", fraction: nil, note: "\(account.provider.displayName) doesn’t count requests")
        }
    }

    private func autoFraction(_ account: Account) -> Double? {
        ledger(account.id).plan?.activeWindows(now: now).map(\.usedPercent).max().map { $0 / 100 }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Răboj: launch at login change failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private static var stateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Raboj", isDirectory: true).appendingPathComponent("state.json")
    }

    private func load() {
        defer { loaded = true }
        guard let data = try? Data(contentsOf: Self.stateURL),
              let state = try? JSONDecoder().decode(StoredState.self, from: data) else { return }
        accounts = state.accounts
        selection = state.selection
        period = state.period
        menuBarMode = state.menuBarMode
        allMetric = state.allMetric ?? .auto
        ignoredClaudeIDs = state.ignoredClaudeIDs ?? []
        if case .account(let id) = selection, account(id) == nil { selection = .all }
    }

    private func save() {
        guard loaded else { return }
        let state = StoredState(accounts: accounts, selection: selection, period: period, menuBarMode: menuBarMode, allMetric: allMetric, ignoredClaudeIDs: ignoredClaudeIDs)
        do {
            try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        } catch {
            NSLog("Răboj: couldn’t save settings: \(error.localizedDescription)")
        }
    }
}
