import AppKit
import RabojCore
import SwiftUI

enum SettingsTab: String, Hashable {
    case general, accounts, accessLog, about
}

/// Selected tab and account. An ObservableObject instead of `@State` (see AddAccountForm).
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab
    @Published var account: UUID?
    init(tab: SettingsTab, account: UUID?) {
        self.tab = tab
        self.account = account
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var navigation: SettingsNavigation

    init(initialTab: SettingsTab, initialAccount: UUID?) {
        _navigation = StateObject(wrappedValue: SettingsNavigation(tab: initialTab, account: initialAccount))
    }

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            AccountsTab(selected: $navigation.account).tabItem { Label("Accounts", systemImage: "person.2") }.tag(SettingsTab.accounts)
            AccessLogTab().tabItem { Label("Access Log", systemImage: "list.bullet.rectangle") }.tag(SettingsTab.accessLog)
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Toggle("Open Răboj at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            Picker("Menu bar shows", selection: $model.menuBarMode) {
                ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
            }
            Text("Tip: ⌥-click the menu bar item to switch accounts without opening the popover; right-click for a menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct AccountsTab: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selected: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(model.accounts) { account in
                        HStack(spacing: 8) {
                            Circle().fill(Color(nsColor: account.color.nsColor)).frame(width: 10, height: 10)
                            ProviderLogoView(provider: account.provider, size: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.label).fontWeight(.semibold)
                                Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let index = model.accounts.firstIndex(of: account), index < 9 {
                                Text("⌘\(index + 1)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(account.id)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                HStack {
                    Button { WindowCoordinator.shared.openAddAccount() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add account")
                    Text("Drag to reorder").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 230)
            Divider()
            Group {
                if let id = selected, let account = model.account(id) {
                    AccountEditor(account: account, onRemoved: { selected = nil }).id(account.id)
                } else {
                    Text(model.accounts.isEmpty ? "No accounts yet." : "Select an account.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selected == nil { selected = model.accounts.first?.id } }
    }
}

/// Editable copy of one account. An ObservableObject instead of `@State` (see AddAccountForm).
final class AccountEditorState: ObservableObject {
    @Published var account: Account
    @Published var newKey = ""
    @Published var confirmRemove = false
    @Published var copied = false
    init(account: Account) { self.account = account }
}

private struct AccountEditor: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var state: AccountEditorState
    let onRemoved: () -> Void

    init(account: Account, onRemoved: @escaping () -> Void) {
        _state = StateObject(wrappedValue: AccountEditorState(account: account))
        self.onRemoved = onRemoved
    }

    private var account: Account { state.account }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $state.account.label)
                LabeledContent("Color") { ColorSwatchPicker(selection: $state.account.color) }
                LabeledContent("Provider") {
                    HStack(spacing: 6) {
                        ProviderLogoView(provider: account.provider, size: 16)
                        Text(account.provider.displayName)
                    }
                }
                Toggle("Include in “All”", isOn: $state.account.includeInAll)
                Toggle("Pin in the menu bar", isOn: $state.account.pinnedInMenuBar)
            }

            switch account.provider.connection {
            case .folder:
                Section("Source") {
                    LabeledContent("Folder") {
                        Text(account.folderPath.map(FolderAccess.displayPath) ?? "—").font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                    }
                    Button("Choose Another Folder…") {
                        if let chosen = FolderAccess.choose(for: account.provider) {
                            state.account.folderPath = chosen.url.path
                            state.account.folderBookmark = chosen.bookmark
                        }
                    }
                    LabeledContent("Network", value: "None: read from local files")
                }
                if account.provider == .claudeCode { claudeLimitsSection }
            case .apiKey:
                Section("Source") {
                    LabeledContent(account.provider.keyName, value: Keychain.read(account.id) == nil ? "Missing" : "Saved in Keychain")
                    if let extra = account.provider.extraFieldName {
                        TextField(extra, text: Binding(get: { state.account.extraID ?? "" }, set: { state.account.extraID = $0.isEmpty ? nil : $0 }))
                    }
                    HStack {
                        SecureField("Replace key", text: $state.newKey)
                        Button("Save") {
                            model.replaceKey(state.newKey.trimmingCharacters(in: .whitespacesAndNewlines), for: account)
                            state.newKey = ""
                        }
                        .disabled(state.newKey.isEmpty)
                    }
                    LabeledContent("Connects to", value: account.provider.allowedHosts.sorted().joined(separator: ", ") + " only")
                    if let docs = account.provider.docsURL { Link("Provider documentation", destination: docs) }
                    Picker("Refresh every", selection: $state.account.refreshMinutes) {
                        ForEach([5, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                    }
                }
            }

            if let error = model.status(account.id).error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }

            Section {
                Button("Remove Account…", role: .destructive) { state.confirmRemove = true }
            } footer: {
                Text(account.provider.connection == .apiKey
                     ? "Removing deletes the key from the Keychain and the saved summary. Nothing changes at the provider."
                     : "Removing drops Răboj’s access and the saved summary. Your files are never changed.")
            }
        }
        .formStyle(.grouped)
        .onReceive(state.$account.dropFirst()) { model.update($0) }
        .confirmationDialog("Remove \(account.label)?", isPresented: $state.confirmRemove) {
            Button("Remove", role: .destructive) {
                model.remove(account.id)
                onRemoved()
            }
        }
    }

    private var claudeLimitsSection: some View {
        Section("Plan limits (Pro, Max, Ultra)") {
            Text("Claude Code passes your 5-hour and weekly limits to its status line. Add this to the settings.json in this folder and Răboj shows them after your next message. It replaces any status line you already have.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(ClaudeStatusLineSetup.settingsSnippet)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            HStack {
                Button(state.copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ClaudeStatusLineSetup.settingsSnippet, forType: .string)
                    state.copied = true
                }
                Spacer()
                if let plan = model.ledger(account.id).plan {
                    Text("Last received \(plan.capturedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not received yet").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AccessLogTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Every network request Răboj made since it started. Folder accounts never use the network.")
                .font(.caption).foregroundStyle(.secondary)
            Table(model.accessLog) {
                TableColumn("Time") { Text($0.date.formatted(date: .omitted, time: .standard)) }.width(80)
                TableColumn("Account", value: \.accountLabel).width(110)
                TableColumn("Host", value: \.host).width(140)
                TableColumn("Endpoint", value: \.path)
                TableColumn("Result", value: \.outcome).width(70)
            }
        }
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: TallyIcon.image(size: 48))
            Text("Răboj").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · MIT License")
                .foregroundStyle(.secondary)
            Text("A răboj is the Romanian tally stick, notched to keep count. This one keeps count of your AI usage.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text("Free and open source. No backend, no tracking, no paywall.")
                .foregroundStyle(.secondary)
            Link("Source on GitHub", destination: URL(string: "https://github.com/MIKALAKE/raboj")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
