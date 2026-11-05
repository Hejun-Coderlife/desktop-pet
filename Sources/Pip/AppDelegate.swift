import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stage: Stage?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let stage = Stage()
        self.stage = stage
        stage.start()
        self.menuBar = MenuBarController(stage: stage)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
