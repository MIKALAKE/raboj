import AppKit
import RabojCore
import SwiftUI

/// One folder chosen in the add-account form; becomes one account.
struct PendingFolder: Identifiable {
    let id = UUID()
    var url: URL
    var bookmark: Data?
    var label: String
    var color: AccountColor
}

/// Form state for AddAccountView. An ObservableObject instead of `@State`, because `@State`
/// is a macro whose plugin ships only with full Xcode, and Răboj must build with the Command Line Tools.
final class AddAccountForm: ObservableObject {
    @Published var provider: Provider?
    @Published var folders: [PendingFolder] = []
    @Published var label = ""
    @Published var color: AccountColor = .blue
    @Published var apiKey = ""
    @Published var extraID = ""
    @Published var testing = false
    @Published var testResult: String?
    @Published var testPassed = false
    @Published var skipped: [String] = []
}

/// Pick a provider, then connect it: one or more folders for local tools, a key for APIs.
struct AddAccountView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var form = AddAccountForm()
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let provider = form.provider {
                    connectForm(for: provider)
                } else {
                    picker
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    // MARK: Step 1: provider

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you want to track?").font(.title2.weight(.semibold))
                Text("Add as many accounts as you like, on any provider. Each one is connected only when you set it up.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            group("On this Mac · no key, no network", providers: Provider.allCases.filter { $0.connection == .folder })
            group("With a key · official usage APIs", providers: Provider.allCases.filter { $0.connection == .apiKey })
            Text("Not available yet, because these services offer no official way to read usage: the ChatGPT, Claude and Gemini apps, the Gemini API (AI Studio), Mistral and Perplexity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func group(_ title: String, providers: [Provider]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            ForEach(providers, id: \.self) { provider in
                Button { select(provider) } label: { providerRow(provider) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        let count = model.accounts.filter { $0.provider == provider }.count
        return HStack(spacing: 12) {
            ProviderLogoView(provider: provider, size: 22)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName).fontWeight(.semibold)
                Text(provider.sourceDescription).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if count > 0 {
                Text("\(count) added").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }

    private func select(_ provider: Provider) {
        let sameProvider = model.accounts.filter { $0.provider == provider }.count
        form.provider = provider
        form.folders = []
        form.skipped = []
        form.label = sameProvider == 0 ? provider.displayName : "\(provider.displayName) \(sameProvider + 1)"
        form.color = model.nextColor
        form.apiKey = ""
        form.extraID = ""
        form.testResult = nil
        form.testPassed = false
    }

    // MARK: Step 2: connect

    @ViewBuilder
    private func connectForm(for provider: Provider) -> some View {
        Button { form.provider = nil } label: { Label("All providers", systemImage: "chevron.left") }
            .buttonStyle(.link)
        HStack(spacing: 10) {
            ProviderLogoView(provider: provider, size: 26)
            Text("Connect \(provider.displayName)").font(.title2.weight(.semibold))
        }

        switch provider.connection {
        case .folder: folderSection(provider)
        case .apiKey: keySection(provider)
        }

        HStack {
            if let docs = provider.docsURL {
                Link("How Răboj reads \(provider.displayName)", destination: docs).font(.caption)
            }
            Spacer()
            Button("Cancel", action: onDone).keyboardShortcut(.cancelAction)
            Button(addTitle(provider)) { add(provider) }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd(provider))
        }
    }

    // MARK: Folders

    private func folderSection(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(folderHelp(provider))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(form.folders.isEmpty ? "Choose Folders…" : "Add More Folders…") { chooseFolders(provider) }
                .controlSize(.large)

            ForEach($form.folders) { $folder in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder")
                        Text(FolderAccess.displayPath(folder.url.path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            form.folders.removeAll { $0.id == folder.id }
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove this folder")
                    }
                    HStack {
                        TextField("Name", text: $folder.label, prompt: Text("e.g. Work"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                        ColorSwatchPicker(selection: $folder.color)
                    }
                    if !FolderReader.looksValid(folder.url, for: provider) {
                        Label("No \(provider.logsSubfolder ?? "") folder inside. Usage may stay empty.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
            }

            ForEach(form.skipped, id: \.self) { path in
                Label("\(path) is already added", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }

            PrivacyNote(lines: [
                "Read-only access to the folders you choose, granted by macOS",
                "Reads token counts, model, time and project name; never your prompts",
                "Nothing leaves your Mac for these accounts",
            ])
        }
    }

    private func folderHelp(_ provider: Provider) -> String {
        switch provider {
        case .claudeCode:
            return "Each Claude Code account keeps its data in its own folder: ~/.claude for the default one, and the folder set in CLAUDE_CONFIG_DIR for the others (for example ~/.claude-personal). Select all of them at once with ⌘-click; Răboj adds one account per folder. Not sure which folder an account uses? Run echo $CLAUDE_CONFIG_DIR where you use it; empty means ~/.claude."
        case .codex:
            return "Codex keeps its data in ~/.codex, or in the folder set in CODEX_HOME. Using several Codex accounts? Select each folder with ⌘-click; Răboj adds one account per folder."
        default:
            return "Gemini CLI keeps its data in ~/.gemini. Choose that folder; Răboj reads the chat recordings in its tmp folder."
        }
    }

    private func chooseFolders(_ provider: Provider) {
        let chosen = FolderAccess.chooseMany(for: provider)
        var used = model.accounts.map(\.color) + form.folders.map(\.color)
        let existing = Set(model.accounts.compactMap(\.folderPath) + form.folders.map(\.url.path))
        form.skipped = []
        for item in chosen {
            guard !existing.contains(item.url.path) else {
                form.skipped.append(FolderAccess.displayPath(item.url.path))
                continue
            }
            let color = AccountColor.next(after: used)
            used.append(color)
            form.folders.append(PendingFolder(url: item.url, bookmark: item.bookmark, label: Self.suggestedName(for: item.url, provider: provider), color: color))
        }
    }

    /// ".claude" → "Claude Code", ".claude-personal" → "Personal", "work" → "Work".
    static func suggestedName(for url: URL, provider: Provider) -> String {
        var name = url.lastPathComponent
        if let sub = provider.logsSubfolder, name == sub { name = url.deletingLastPathComponent().lastPathComponent }
        if let base = provider.defaultFolderName {
            if name == base { return provider.displayName }
            for separator in ["-", "_", "."] where name.hasPrefix(base + separator) {
                name = String(name.dropFirst(base.count + 1))
            }
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        return name.isEmpty ? provider.displayName : name.replacingOccurrences(of: "-", with: " ").capitalized
    }

    // MARK: Key

    private func keySection(_ provider: Provider) -> some View {
        let host = provider.allowedHosts.sorted().joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 12) {
            Text(provider.keyHelp)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Name")
                    TextField("Name", text: $form.label, prompt: Text("e.g. Team")).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Color")
                    ColorSwatchPicker(selection: $form.color)
                }
                if let extra = provider.extraFieldName {
                    GridRow {
                        Text(extra)
                        TextField(extra, text: $form.extraID).textFieldStyle(.roundedBorder)
                    }
                }
                GridRow {
                    Text("Key")
                    SecureField(provider.keyName, text: $form.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: form.apiKey) {
                            form.testResult = nil
                            form.testPassed = false
                        }
                }
            }
            HStack {
                Button(form.testing ? "Testing…" : "Test Connection") { test(provider) }
                    .disabled(form.apiKey.isEmpty || form.testing)
                if let result = form.testResult {
                    Label(result, systemImage: form.testPassed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(form.testPassed ? Color.green : Color.red)
                        .lineLimit(3)
                }
            }
            PrivacyNote(lines: [
                "Saved in your macOS Keychain, not in a file",
                "Sent only to \(host), over HTTPS",
                "Used only for the usage, cost or balance endpoints",
                "Every request is listed in Settings › Access Log",
                "Removing the account deletes the key",
            ])
        }
    }

    private func test(_ provider: Provider) {
        form.testing = true
        let key = form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = form.label
        let extra = form.extraID.trimmingCharacters(in: .whitespaces)
        Task {
            let error = await model.test(key: key, provider: provider, label: label, extraID: extra.isEmpty ? nil : extra)
            form.testing = false
            form.testPassed = error == nil
            form.testResult = error ?? "Connection works"
        }
    }

    // MARK: Add

    private func addTitle(_ provider: Provider) -> String {
        provider.connection == .folder && form.folders.count > 1 ? "Add \(form.folders.count) Accounts" : "Add Account"
    }

    private func canAdd(_ provider: Provider) -> Bool {
        switch provider.connection {
        case .folder:
            return !form.folders.isEmpty && form.folders.allSatisfy { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        case .apiKey:
            guard !form.label.trimmingCharacters(in: .whitespaces).isEmpty, !form.apiKey.isEmpty else { return false }
            return provider.extraFieldName == nil || !form.extraID.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func add(_ provider: Provider) {
        switch provider.connection {
        case .folder:
            let accounts = form.folders.map { folder in
                Account(provider: provider, label: folder.label.trimmingCharacters(in: .whitespaces), color: folder.color, folderPath: folder.url.path, folderBookmark: folder.bookmark)
            }
            model.add(accounts, apiKey: nil)
            onDone()
            if provider == .claudeCode, let first = accounts.first {
                WindowCoordinator.shared.openSettings(tab: .accounts, account: first.id)
            }
        case .apiKey:
            let extra = form.extraID.trimmingCharacters(in: .whitespaces)
            let account = Account(provider: provider, label: form.label.trimmingCharacters(in: .whitespaces), color: form.color, extraID: extra.isEmpty ? nil : extra)
            model.add(account, apiKey: form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            onDone()
        }
    }
}

struct PrivacyNote: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(lines, id: \.self) { line in
                Label(line, systemImage: "checkmark").font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
