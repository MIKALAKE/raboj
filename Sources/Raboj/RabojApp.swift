import AppKit

@main
enum RabojMain {
    /// Kept alive for the whole run; NSApplication holds its delegate weakly.
    private static var delegate: AppDelegate?

    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--report") {
            Report.run(Array(arguments.dropFirst(index + 1)))
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel()
        self.model = model
        WindowCoordinator.shared.model = model
        statusItem = StatusItemController(model: model)
        model.start()
        if model.accounts.isEmpty {
            WindowCoordinator.shared.openAddAccount()
        }
    }
}
