import AppKit

/// 菜单栏图标：显示/隐藏、暂停、退出
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private weak var stage: Stage?

    init(stage: Stage) {
        self.stage = stage
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pip")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Pip"
        }

        let menu = NSMenu()
        menu.delegate = self

        let hideItem = NSMenuItem(title: "隐藏小人", action: #selector(toggleHidden), keyEquivalent: "h")
        hideItem.target = self
        menu.addItem(hideItem)

        let pauseItem = NSMenuItem(title: "暂停（停在原地不动）", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Pip", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    var isReady: Bool { statusItem.button != nil }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let stage else { return }
        menu.item(at: 0)?.title = stage.isUserHidden ? "显示小人" : "隐藏小人"
        if let pauseItem = menu.item(at: 1) {
            pauseItem.state = stage.isPaused ? .on : .off
            pauseItem.title = stage.isPaused ? "继续动画" : "暂停（停在原地不动）"
        }
    }

    @objc private func toggleHidden() { stage?.toggleHidden() }
    @objc private func togglePause() { stage?.togglePaused() }
    @objc private func quit() {
        stage?.resetCursor()
        NSApp.terminate(nil)
    }
}
