import AppKit
import Combine
import RabojCore
import SwiftUI

extension Notification.Name {
    static let rabojClosePopover = Notification.Name("RabojClosePopover")
}

/// The menu bar item: number(s) with account-colored dots, a popover on click,
/// ⌥-click to cycle accounts, right-click (or ⌃-click) for a menu.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var observation: AnyCancellable?
    private var closeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView().environmentObject(model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        if let button = item.button {
            button.image = TallyIcon.image()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Răboj")
        }

        observation = model.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
        closeObserver = NotificationCenter.default.addObserver(forName: .rabojClosePopover, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
        updateTitle()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if event?.modifierFlags.contains(.option) == true {
            model.cycleSelection()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Add Account…", action: #selector(addAccount), keyEquivalent: "n").target = self
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Răboj", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func addAccount() { WindowCoordinator.shared.openAddAccount() }
    @objc private func refresh() { model.refreshAll() }
    @objc private func settings() { WindowCoordinator.shared.openSettings() }

    /// Changing the title while the popover is open would resize the item and drag the popover sideways,
    /// so the title waits until the popover closes.
    func popoverDidClose(_ notification: Notification) {
        updateTitle()
    }

    private func updateTitle() {
        guard let button = item.button, !popover.isShown else { return }
        let parts = titleParts()
        guard !parts.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            return
        }
        button.imagePosition = .imageLeading
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .medium)
        let title = NSMutableAttributedString(string: " ")
        for (index, part) in parts.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  ")) }
            title.append(NSAttributedString(string: "●", attributes: [.foregroundColor: part.color, .font: NSFont.systemFont(ofSize: 8), .baselineOffset: 1.5]))
            title.append(NSAttributedString(string: " " + part.text, attributes: [.font: font]))
        }
        button.attributedTitle = title
        button.setAccessibilityValue(parts.map(\.text).joined(separator: ", "))
    }

    private func titleParts() -> [(color: NSColor, text: String)] {
        let part: (Account) -> (NSColor, String) = { ($0.nsColor, self.model.value($0, metric: self.model.allMetric).text) }
        let single: (Account) -> (NSColor, String) = { ($0.nsColor, self.model.headline($0)) }
        switch model.menuBarMode {
        case .iconOnly:
            return []
        case .pinned:
            let pinned = model.accounts.filter(\.pinnedInMenuBar)
            return (pinned.isEmpty ? Array(model.accounts.prefix(3)) : pinned).map(part)
        case .selection:
            if case .account(let id) = model.selection, let account = model.account(id) { return [single(account)] }
            let pinned = model.accounts.filter(\.pinnedInMenuBar)
            return (pinned.isEmpty ? Array(model.accounts.filter(\.includeInAll).prefix(3)) : pinned).map(part)
        }
    }
}

/// Opens and reuses the app's windows (settings, add account).
@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = WindowCoordinator()
    var model: AppModel?
    private var windows: [String: NSWindow] = [:]

    func openSettings(tab: SettingsTab = .accounts, account: UUID? = nil) {
        guard let model else { return }
        show(id: "settings", title: "Răboj Settings", size: NSSize(width: 760, height: 540)) {
            SettingsView(initialTab: tab, initialAccount: account).environmentObject(model)
        }
    }

    func openAddAccount() {
        guard let model else { return }
        show(id: "add", title: "Add an Account", size: NSSize(width: 520, height: 640)) {
            AddAccountView(onDone: { [weak self] in self?.close("add") }).environmentObject(model)
        }
    }

    func close(_ id: String) { windows[id]?.close() }

    private func show<Content: View>(id: String, title: String, size: NSSize, content: () -> Content) {
        NotificationCenter.default.post(name: .rabojClosePopover, object: nil)
        if let window = windows[id] {
            window.contentViewController = NSHostingController(rootView: content())
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let key = windows.first(where: { $0.value === window })?.key else { return }
        windows[key] = nil
    }
}
