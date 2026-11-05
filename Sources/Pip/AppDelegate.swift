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

    /// 菜单栏图标被刘海挡住时：再双击一次 Pip.app，藏起来的小人会重新出现
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let stage, stage.isUserHidden { stage.toggleHidden() }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
