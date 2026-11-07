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

    private var readers: [UUID: FolderReader] = [:]
    private var lastAPIFetch: [UUID: Date] = [:]
    /// End of the last successful API fetch, so later fetches only ask for recent days.
    private var apiFetchedThrough: [UUID: Date] = [:]
    private var apiTasks: [UUID: Task<Void, Never>] = [:]
    private var timer: Timer?
    private let transport = URLSessionTransport()
    private var loaded = false

    init() { load() }

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
        guard accounts.contains(where: { $0.id == id }) else { return }
        var status = statuses[id] ?? AccountStatus()
        status.loading = false
        status.error = result.error
        if result.error == nil { status.lastUpdated = Date() }
        statuses[id] = status
        guard !result.events.isEmpty || result.plan != nil || result.info != nil || ledgers[id] == nil else { return }
        var ledger = ledgers[id] ?? UsageLedger()
        ledger.merge(result.events)
        ledger.offer(plan: result.plan)
        if let info = result.info { ledger.info = info }
        ledger.prune(before: Date().addingTimeInterval(-FolderReader.retention))
        ledgers[id] = ledger
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
        let folderChanged = accounts[index].folderBookmark != account.folderBookmark || accounts[index].folderPath != account.folderPath
        let sourceChanged = accounts[index].extraID != account.extraID
        accounts[index] = account
        save()
        if folderChanged {
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
        if case .account(let id) = selection, account(id) == nil { selection = .all }
    }

    private func save() {
        guard loaded else { return }
        let state = StoredState(accounts: accounts, selection: selection, period: period, menuBarMode: menuBarMode)
        do {
            try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.stateURL, options: .atomic)
        } catch {
            NSLog("Răboj: couldn’t save settings: \(error.localizedDescription)")
        }
    }
}
