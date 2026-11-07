import RabojCore
import SwiftUI

/// Form state for AddAccountView. An ObservableObject instead of `@State`, because `@State`
/// is a macro whose plugin ships only with full Xcode, and Răboj must build with the Command Line Tools.
final class AddAccountForm: ObservableObject {
    @Published var provider: Provider?
    @Published var label = ""
    @Published var color: AccountColor = .blue
    @Published var folderURL: URL?
    @Published var folderBookmark: Data?
    @Published var apiKey = ""
    @Published var testing = false
    @Published var testResult: String?
    @Published var testPassed = false
}

/// Pick a provider, then connect it: a folder for local tools, an admin key for APIs.
struct AddAccountView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var form = AddAccountForm()
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let provider = form.provider {
                connectForm(for: provider)
            } else {
                picker
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 500, alignment: .topLeading)
    }

    // MARK: Step 1

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you want to track?").font(.title2.weight(.semibold))
                Text("Add as many accounts as you like, on any provider. Each one is connected only when you set it up.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Provider.allCases, id: \.self) { provider in
                Button {
                    select(provider)
                } label: {
                    HStack(spacing: 12) {
                        Text(provider.monogram)
                            .font(.caption.weight(.bold))
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName).fontWeight(.semibold)
                            Text(provider.sourceDescription).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("More providers are added only when they offer an official API or local logs to read usage from.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func select(_ provider: Provider) {
        let sameProvider = model.accounts.filter { $0.provider == provider }.count
        form.provider = provider
        form.label = sameProvider == 0 ? provider.displayName : "\(provider.displayName) \(sameProvider + 1)"
        form.color = model.nextColor
        form.folderURL = nil
        form.folderBookmark = nil
        form.apiKey = ""
        form.testResult = nil
        form.testPassed = false
    }

    // MARK: Step 2

    @ViewBuilder
    private func connectForm(for provider: Provider) -> some View {
        Button { form.provider = nil } label: { Label("All providers", systemImage: "chevron.left") }
            .buttonStyle(.link)
        Text(provider.connection == .folder ? "Connect \(provider.displayName)" : "Connect with an Admin API key")
            .font(.title2.weight(.semibold))

        Form {
            TextField("Name", text: $form.label, prompt: Text("e.g. Work"))
            Picker("Color", selection: $form.color) {
                ForEach(AccountColor.allCases, id: \.self) { option in
                    Label(option.title, systemImage: "circle.fill").foregroundStyle(Color(nsColor: option.nsColor)).tag(option)
                }
            }
        }
        .formStyle(.columns)

        switch provider.connection {
        case .folder: folderSection(provider)
        case .apiKey: keySection(provider)
        }

        Spacer(minLength: 0)
        HStack {
            Spacer()
            Button("Cancel", action: onDone).keyboardShortcut(.cancelAction)
            Button("Add Account") { add(provider) }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd(provider))
        }
    }

    private func folderSection(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(provider == .claudeCode
                 ? "Choose the folder Claude Code keeps its data in: usually ~/.claude, or the folder in CLAUDE_CONFIG_DIR if you use several accounts."
                 : "Choose the folder Codex keeps its data in: usually ~/.codex, or the folder in CODEX_HOME.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(form.folderURL == nil ? "Choose Folder…" : "Choose Another…") {
                    if let chosen = FolderAccess.choose(for: provider) {
                        form.folderURL = chosen.url
                        form.folderBookmark = chosen.bookmark
                    }
                }
                if let url = form.folderURL {
                    Text(FolderAccess.displayPath(url.path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
                }
            }
            if let url = form.folderURL, !FolderReader.looksValid(url, for: provider) {
                Label("This folder has no \(provider == .codex ? "sessions" : "projects") folder inside. Usage may stay empty.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            PrivacyNote(lines: [
                "Read-only access to this folder only, granted by macOS",
                "Reads token counts, model, time and project name; never your prompts",
                "Nothing leaves your Mac for this account",
            ])
        }
    }

    private func keySection(_ provider: Provider) -> some View {
        let host = provider.allowedHosts.sorted().joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 10) {
            Text(provider == .anthropicAPI
                 ? "Organization admins can create an Admin API key (sk-ant-admin…) in the Claude Console. Răboj uses it only to read usage and cost reports."
                 : "Organization owners can create an Admin key in the OpenAI platform settings. Răboj uses it only to read usage and costs.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Admin API key", text: $form.apiKey)
                .textFieldStyle(.roundedBorder)
                .onChange(of: form.apiKey) {
                    form.testResult = nil
                    form.testPassed = false
                }
            HStack {
                Button(form.testing ? "Testing…" : "Test Connection") { test(provider) }
                    .disabled(form.apiKey.isEmpty || form.testing)
                if let result = form.testResult {
                    Label(result, systemImage: form.testPassed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(form.testPassed ? Color.green : Color.red)
                        .lineLimit(2)
                }
            }
            PrivacyNote(lines: [
                "Saved in your macOS Keychain, not in a file",
                "Sent only to \(host), over HTTPS",
                "Used only for the usage and cost endpoints",
                "Every request is listed in Settings › Access Log",
                "Removing the account deletes the key",
            ])
        }
    }

    private func test(_ provider: Provider) {
        form.testing = true
        let key = form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountLabel = form.label
        Task {
            let error = await model.test(key: key, provider: provider, label: accountLabel)
            form.testing = false
            form.testPassed = error == nil
            form.testResult = error ?? "Connection works"
        }
    }

    private func canAdd(_ provider: Provider) -> Bool {
        guard !form.label.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch provider.connection {
        case .folder: return form.folderURL != nil
        case .apiKey: return !form.apiKey.isEmpty
        }
    }

    private func add(_ provider: Provider) {
        let account = Account(
            provider: provider,
            label: form.label.trimmingCharacters(in: .whitespaces),
            color: form.color,
            folderPath: form.folderURL?.path,
            folderBookmark: form.folderBookmark
        )
        let key = provider.connection == .apiKey ? form.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        model.add(account, apiKey: key)
        onDone()
        if provider == .claudeCode {
            WindowCoordinator.shared.openSettings(tab: .accounts, account: account.id)
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
