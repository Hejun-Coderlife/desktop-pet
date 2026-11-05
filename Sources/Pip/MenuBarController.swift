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

        for (title, key) in [("爬到窗口上", "climb"), ("有声音时跳舞", "dance"), ("节日装扮（重开 Pip 生效）", "outfit"), ("定时举牌提醒", "remind")] {
            let item = NSMenuItem(title: title, action: #selector(toggleFeature(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(makeVolumeItem())

        menu.addItem(.separator())
        let interval = NSMenuItem(title: "提醒间隔", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for minutes in [20, 30, 45, 60, 90] {
            let item = NSMenuItem(title: "\(minutes) 分钟", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            sub.addItem(item)
        }
        interval.submenu = sub
        menu.addItem(interval)
        let now = NSMenuItem(title: "现在提醒一下", action: #selector(remindNow), keyEquivalent: "")
        now.target = self
        menu.addItem(now)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Pip", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        stage.contextMenu = menu
    }

    var isReady: Bool { statusItem.button != nil }

    // MARK: 音量（Pip 自己的，和系统音量分开）

    private let volumeLabel = NSTextField(labelWithString: "")
    private let volumeSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)

    private func makeVolumeItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 48))
        volumeLabel.frame = NSRect(x: 20, y: 26, width: 210, height: 17)
        volumeLabel.font = .menuFont(ofSize: 0)
        volumeSlider.frame = NSRect(x: 18, y: 4, width: 206, height: 22)
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        volumeSlider.isContinuous = true
        view.addSubview(volumeLabel)
        view.addSubview(volumeSlider)
        let item = NSMenuItem()
        item.view = view
        syncVolume()
        return item
    }

    private func syncVolume() {
        let v = Int((Settings.volume * 100).rounded())
        volumeSlider.integerValue = v
        volumeLabel.stringValue = v == 0 ? "Pip 的声音：静音" : "Pip 的声音：\(v)%"
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        Settings.volume = sender.doubleValue / 100
        syncVolume()
        // 松手时出一声，让人听到现在多大声
        if NSApp.currentEvent?.type == .leftMouseUp { Voice.shared.play(.hop) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let stage else { return }
        syncVolume()
        menu.item(at: 0)?.title = stage.isUserHidden ? "显示小人" : "隐藏小人"
        if let pauseItem = menu.item(at: 1) {
            pauseItem.state = stage.isPaused ? .on : .off
            pauseItem.title = stage.isPaused ? "继续动画" : "暂停（停在原地不动）"
        }
        for item in menu.items {
            switch item.representedObject as? String {
            case "climb": item.state = Settings.climbWindows ? .on : .off
            case "dance": item.state = Settings.dance ? .on : .off
            case "outfit": item.state = Outfit.enabled ? .on : .off
            case "remind": item.state = Settings.reminders ? .on : .off
            default: break
            }
            item.submenu?.items.forEach { $0.state = Double($0.tag) == Settings.reminderMinutes ? .on : .off }
        }
    }

    @objc private func toggleFeature(_ sender: NSMenuItem) {
        switch sender.representedObject as? String {
        case "climb": Settings.climbWindows.toggle()
        case "dance": Settings.dance.toggle()
        case "outfit": Outfit.enabled.toggle()
        case "remind": Settings.reminders.toggle()
        default: break
        }
    }
    @objc private func setInterval(_ sender: NSMenuItem) { Settings.reminderMinutes = Double(sender.tag) }
    @objc private func remindNow() { stage?.remindNow() }

    @objc private func toggleHidden() { stage?.toggleHidden() }
    @objc private func togglePause() { stage?.togglePaused() }
    @objc private func quit() {
        stage?.resetCursor()
        NSApp.terminate(nil)
    }
}
