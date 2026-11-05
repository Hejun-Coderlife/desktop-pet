import AppKit
import SceneKit
import CoreAudio

// MARK: - 开关（菜单栏里改，记在 UserDefaults）

enum Settings {
    private static func flag(_ key: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? def }
    static var climbWindows: Bool { get { flag("climbWindows", true) } set { UserDefaults.standard.set(newValue, forKey: "climbWindows") } }
    static var dance: Bool { get { flag("dance", true) } set { UserDefaults.standard.set(newValue, forKey: "dance") } }
    static var reminders: Bool { get { flag("reminders", true) } set { UserDefaults.standard.set(newValue, forKey: "reminders") } }
    /// 提醒间隔（分钟，按「真的在用电脑」的时间累计）
    static var reminderMinutes: Double { get { (UserDefaults.standard.object(forKey: "reminderMinutes") as? Double) ?? 45 } set { UserDefaults.standard.set(newValue, forKey: "reminderMinutes") } }
}

// MARK: - 不抢焦点、不进程序坞的透明舞台窗口

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 只负责把鼠标事件转给 Stage
final class PetSceneView: SCNView {
    weak var stage: Stage?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        stage?.petMouseDown()
    }

    override func mouseDragged(with event: NSEvent) {
        stage?.petMouseDragged()
    }

    override func mouseUp(with event: NSEvent) {
        stage?.petMouseUp()
    }
}

// MARK: - 舞台

final class Stage {

    private let panel: PetPanel
    private let sceneView: PetSceneView
    private let scene: SCNScene
    private let cameraNode: SCNNode
    private let rig: PipRig
    private let shadowNode: SCNNode
    private let world: PetWorld

    private var currentScreen: NSScreen
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTickTime: CFTimeInterval = CACurrentMediaTime()
    private var lastEnvironmentCheck: CFTimeInterval = 0

    private var userHidden = false
    private var paused = false
    private var fullscreenHidden = false
    private var occluded = false
    private var screenObserver: NSObjectProtocol?

    /// 眼神方向（-1…1），逐帧平滑逼近鼠标方向
    private var gaze = CGPoint.zero
    /// 当前系统光标，避免每帧重复 set()
    private var cursorStyle = CursorStyle.arrow

    // 互动
    private var lastMouse = CGPoint.zero
    private var mouseStillSince: CFTimeInterval = CACurrentMediaTime()
    private var downTime: CFTimeInterval = 0
    private var downPoint = CGPoint.zero
    // 提醒
    private var activeSeconds: Double = 0
    private var reminderIndex = 0
    private static let reminderTexts = ["喝口水吧 💧", "站起来走走 🚶", "看看远处 👀", "伸个懒腰 🙆"]

    // MARK: 初始化

    init(screen: NSScreen? = nil) {
        let primary = screen ?? NSScreen.screens.first ?? NSScreen.main!
        currentScreen = primary

        let frame = primary.frame
        let groundY = primary.visibleFrame.minY - frame.minY

        let built = SceneFactory.makeScene(viewportSize: frame.size)
        scene = built.scene
        cameraNode = built.camera
        rig = built.rig
        shadowNode = built.shadow

        sceneView = PetSceneView(frame: CGRect(origin: .zero, size: Stage.boxSize), options: nil)
        sceneView.scene = scene
        sceneView.pointOfView = cameraNode
        sceneView.backgroundColor = .clear
        sceneView.wantsLayer = true
        sceneView.layer?.backgroundColor = NSColor.clear.cgColor
        sceneView.layer?.isOpaque = false
        sceneView.antialiasingMode = .multisampling4X
        sceneView.isPlaying = true
        sceneView.preferredFramesPerSecond = 30
        sceneView.rendersContinuously = false
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false

        panel = PetPanel(contentRect: CGRect(origin: frame.origin, size: Stage.boxSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered,
                         defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // 程序坞层级之上，菜单栏之下
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        panel.contentView = sceneView

        world = PetWorld(size: frame.size, groundY: groundY, seed: 0x9E37_79B9)

        sceneView.stage = self
    }

    // MARK: 生命周期

    func start() {
        applyVisuals()
        panel.orderFrontRegardless()
        lastTickTime = CACurrentMediaTime()
        schedule(interval: 0.1)
        // 换屏幕 / 改分辨率 / 程序坞换边都会发这个通知，收到就立刻重算地面
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshEnvironment()
        }
    }

    /// 冒烟测试：不显示窗口，把「世界更新 → 生成姿势 → 应用到模型 → 调整帧率」整条管线跑几秒
    func smokeTest(seconds: TimeInterval) -> String {
        let dt: CGFloat = 1.0 / 30.0
        let steps = Int(seconds / TimeInterval(dt))
        var sequence: [String] = []
        for _ in 0..<steps {
            updateMouse(dt: dt)
            world.update(dt: dt)
            applyVisuals()
            updateFrameRate()
            if sequence.last != world.state.displayName {
                sequence.append(world.state.displayName)
            }
        }
        let fps = timerInterval > 0 ? Int((1.0 / timerInterval).rounded()) : 0
        return "状态序列 \(sequence.joined(separator: " → "))"
            + "，最终位置 x=\(String(format: "%.1f", Double(world.position.x)))"
            + " y=\(String(format: "%.1f", Double(world.position.y)))"
            + "，目标帧率 \(fps) fps"
    }

    // MARK: 配置自检（不开窗口，只打印关键属性）

    func debugSummary() -> String {
        var lines: [String] = []
        lines.append("屏幕 frame      = \(rectString(currentScreen.frame))")
        lines.append("屏幕 visibleFrame = \(rectString(currentScreen.visibleFrame))")
        lines.append("窗口 frame      = \(rectString(panel.frame))")
        lines.append("地面 y（窗口内）= \(String(format: "%.1f", world.groundY)) 点")
        lines.append("窗口层级        = \(panel.level.rawValue)（程序坞 \(CGWindowLevelForKey(.dockWindow))，菜单栏 \(CGWindowLevelForKey(.mainMenuWindow))）")
        lines.append("ignoresMouseEvents = \(panel.ignoresMouseEvents)")
        lines.append("isOpaque        = \(panel.isOpaque)")
        lines.append("hasShadow       = \(panel.hasShadow)")
        lines.append("canBecomeKey    = \(panel.canBecomeKey)")
        lines.append("collectionBehavior = \(panel.collectionBehavior.rawValue)"
                     + "（canJoinAllSpaces=\(panel.collectionBehavior.contains(.canJoinAllSpaces))"
                     + " stationary=\(panel.collectionBehavior.contains(.stationary))"
                     + " fullScreenNone=\(panel.collectionBehavior.contains(.fullScreenNone))）")
        lines.append("相机正交高度     = \(cameraNode.camera?.orthographicScale ?? 0)（窗口高的一半 = \(panel.frame.height / 2)）")
        lines.append("角色尺寸        = \(world.halfWidth * 2) x \(world.characterHeight) 点")
        let r = petRect()
        lines.append("点击区域        = \(rectString(r))")
        lines.append("当前状态        = \(world.state.displayName)，位置 \(rectString(CGRect(x: world.position.x, y: world.position.y, width: 0, height: 0)))")
        let plat = FrontmostAppWindow.topEdge(on: currentScreen, groundY: world.groundY)
        lines.append("可站的窗口顶边  = \(plat.map { "id=\($0.id) x=\(Int($0.x0))…\(Int($0.x1)) y=\(Int($0.y))" } ?? "无")")
        let all = FrontmostAppWindow.allTopEdges(on: currentScreen, groundY: world.groundY)
        lines.append("所有可站的顶边  = \(all.count) 个：" + all.prefix(6).map { "y=\(Int($0.y)) x=\(Int($0.x0))…\(Int($0.x1))" }.joined(separator: "，"))
        lines.append("有声音在放      = \(SoundOutput.isPlaying())")
        let anyInput = CGEventType(rawValue: ~0)!
        lines.append("系统空闲秒数    = \(String(format: "%.1f", CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)))")
        lines.append("节日装扮        = \(Outfit.current().rawValue)")
        return lines.joined(separator: "\n")
    }

    private func rectString(_ rect: CGRect) -> String {
        String(format: "x=%.0f y=%.0f w=%.0f h=%.0f", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }

    // MARK: 菜单栏接口

    var isPaused: Bool { paused }
    var isUserHidden: Bool { userHidden }

    func togglePaused() {
        paused.toggle()
        if paused {
            panel.ignoresMouseEvents = true
            sceneView.isPlaying = false
        } else {
            lastTickTime = CACurrentMediaTime()
            sceneView.isPlaying = true
        }
    }

    func toggleHidden() {
        userHidden.toggle()
        if userHidden {
            panel.orderOut(nil)
        } else if !fullscreenHidden {
            panel.orderFrontRegardless()
        }
    }

    // MARK: 主循环

    private func schedule(interval: TimeInterval) {
        guard abs(interval - timerInterval) > 0.0001 else { return }
        timerInterval = interval
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        newTimer.tolerance = interval * 0.15
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        sceneView.preferredFramesPerSecond = Int((1.0 / interval).rounded())
    }

    private enum CursorStyle {
        case arrow, openHand, closedHand

        var cursor: NSCursor {
            switch self {
            case .arrow: return .arrow
            case .openHand: return .openHand
            case .closedHand: return .closedHand
            }
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let rawDt = now - lastTickTime
        lastTickTime = now
        let dt = CGFloat(min(max(rawDt, 0), 0.12))

        if now - lastEnvironmentCheck > 0.5 {
            lastEnvironmentCheck = now
            refreshEnvironment()
        }

        guard !paused, !userHidden, !fullscreenHidden, !occluded else {
            sceneView.isPlaying = false
            applyCursor(.arrow)
            return
        }

        sceneView.isPlaying = true
        feedInputs(dt: Double(dt))
        updateMouse(dt: dt)
        world.update(dt: dt)
        applyVisuals()
        updateFrameRate()
    }

    /// 系统空闲时间（不需要任何权限）、提醒计时
    private func feedInputs(dt: Double) {
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        world.idleSeconds = idle
        if idle < 60 { activeSeconds += dt }
        if Settings.reminders && activeSeconds >= Settings.reminderMinutes * 60 {
            activeSeconds = 0
            world.showSign(Self.reminderTexts[reminderIndex % Self.reminderTexts.count])
            reminderIndex += 1
        }
    }

    /// 菜单栏「现在提醒一下」用来试效果
    func remindNow() {
        activeSeconds = 0
        world.showSign(Self.reminderTexts[reminderIndex % Self.reminderTexts.count])
        reminderIndex += 1
    }

    private func updateFrameRate() {
        let interval: TimeInterval = world.isMoving ? (1.0 / 30.0) : (1.0 / 10.0)
        schedule(interval: interval)
    }

    // MARK: 环境（屏幕 / 程序坞 / 遮挡 / 全屏）

    private func refreshEnvironment() {
        let screen = NSScreen.screens.first ?? NSScreen.main ?? currentScreen
        let frame = screen.frame
        let groundY = screen.visibleFrame.minY - frame.minY

        if screen !== currentScreen || frame != currentScreen.frame {
            currentScreen = screen
            world.setGeometry(size: frame.size, groundY: groundY)
            boxOrigin = CGPoint(x: -1, y: -1)
            layoutBox()
        } else if abs(groundY - world.groundY) > 0.5 {
            // 程序坞隐藏 / 换边 / 改大小
            world.setGeometry(size: frame.size, groundY: groundY)
        }

        occluded = panel.isVisible && !panel.occlusionState.contains(.visible)

        world.climbEnabled = Settings.climbWindows
        world.setPlatform(Settings.climbWindows ? FrontmostAppWindow.topEdge(on: screen, groundY: groundY) : nil)
        world.setPlatforms(Settings.climbWindows ? FrontmostAppWindow.allTopEdges(on: screen, groundY: groundY) : [])
        world.soundPlaying = Settings.dance && SoundOutput.isPlaying()

        let fs = FrontmostAppWindow.isFullscreen(on: screen)
        if fs != fullscreenHidden {
            fullscreenHidden = fs
            if fs {
                panel.orderOut(nil)
            } else if !userHidden {
                panel.orderFrontRegardless()
            }
        }
    }

    private func updateCamera(viewportSize: CGSize) {
        cameraNode.position = SCNVector3(viewportSize.width / 2, viewportSize.height / 2, 1200)
        cameraNode.camera?.orthographicScale = Double(max(1, viewportSize.height / 2))
    }

    // MARK: 鼠标

    /// 鼠标在「舞台坐标」里的位置（主屏左下为原点，和 PetWorld 一致；窗口本身只是跟着 Pip 走的小框）
    private func eventPoint() -> CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x - currentScreen.frame.minX, y: p.y - currentScreen.frame.minY)
    }

    /// 窗口不再铺满全屏（全屏透明窗口会被截图的「选窗口」模式选中，截出一张空图；调度中心里也有个空框），
    /// 而是一个跟着 Pip 走的小框。场景坐标不变，相机对准小框。
    static let boxSize = CGSize(width: 320, height: 300)
    private var boxOrigin = CGPoint(x: -1, y: -1)

    private func layoutBox() {
        let b = Self.boxSize
        let size = currentScreen.frame.size
        var o = CGPoint(x: world.position.x - b.width / 2, y: world.position.y - 46)
        o.x = min(max(o.x, 0), max(0, size.width - b.width))
        o.y = min(max(o.y, 0), max(0, size.height - b.height))
        o = CGPoint(x: o.x.rounded(), y: o.y.rounded())
        guard o != boxOrigin else { return }
        boxOrigin = o
        panel.setFrameOrigin(CGPoint(x: o.x + currentScreen.frame.minX, y: o.y + currentScreen.frame.minY))
        cameraNode.position = SCNVector3(o.x + b.width / 2, o.y + b.height / 2, 1200)
        cameraNode.camera?.orthographicScale = Double(b.height / 2)
    }

    /// 小人的点击区域（窗口/视图坐标，1:1 点）
    private func petRect() -> CGRect {
        // 躺着睡时身子横在地上，朝面向的一侧伸出去约 90 点
        if world.state == .sleep {
            let x0 = world.facing > 0 ? world.position.x - 34 : world.position.x - 96
            return CGRect(x: x0, y: world.position.y - 6, width: 130, height: 66)
        }
        let width = world.halfWidth * 2 + 10
        let height = world.characterHeight
        return CGRect(x: world.position.x - width / 2,
                      y: world.position.y - 6,
                      width: width,
                      height: height + 6)
    }

    private func updateMouse(dt: CGFloat) {
        let point = eventPoint()

        if world.state == .grabbed {
            // 鼠标已经松开（比如事件丢了），兜底结束拖拽
            if NSEvent.pressedMouseButtons & 1 == 0 {
                world.endGrab()
                panel.ignoresMouseEvents = !petRect().contains(point)
                updateLook(at: point)
                return
            }
            panel.ignoresMouseEvents = false
            world.drag(to: point)
            updateLook(at: point)
            return
        }

        let inside = petRect().contains(point)
        let shouldIgnore = !inside
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }

        // 摸头：没按键、在它身上来回划。划得越多越舒服（太快的一扫而过不算）
        let moved = hypot(point.x - lastMouse.x, point.y - lastMouse.y)
        let now = CACurrentMediaTime()
        if moved > 1.5 { mouseStillSince = now }
        if inside && NSEvent.pressedMouseButtons & 1 == 0 && moved > 0.5 && moved < 60 {
            world.pet(amount: moved / 260)
        }
        lastMouse = point

        // 追鼠标：光标停在脚下附近不动 1.5 秒，它就慢慢走过去抬头看
        let nearFloor = point.y - world.supportY < 160 && point.y > world.groundY - 40
        if !inside && nearFloor && now - mouseStillSince > 1.5 {
            world.attentionX = min(max(point.x, world.halfWidth), world.size.width - world.halfWidth)
        } else if moved > 1.5 || !nearFloor {
            world.attentionX = nil
        }
        updateLook(at: point)
    }

    /// 眼神跟着鼠标走 + 光标形状（悬停=张开手，拎着=握手）
    private func updateLook(at point: CGPoint) {
        // 脸的中心：脚底往上 62 点
        let faceX = world.position.x
        let faceY = world.position.y + 62
        // 鼠标走近到 320 点以内才跟着看，走远了就望回正前方
        let dx = point.x - faceX
        let dy = point.y - faceY
        let engaged = hypot(dx, dy) < 320
        let targetX = engaged ? max(-1, min(1, dx / 110)) : 0
        let targetY = engaged ? max(-1, min(1, dy / 110)) : 0

        gaze.x += (targetX - gaze.x) * 0.22
        gaze.y += (targetY - gaze.y) * 0.22
        // 角色朝左时根节点是镜像的，局部 x 要跟着翻
        rig.setGaze(CGPoint(x: gaze.x * world.facing, y: gaze.y))

        if world.state == .grabbed {
            applyCursor(.closedHand)
        } else if petRect().contains(point) {
            applyCursor(.openHand)
        } else {
            applyCursor(.arrow)
        }
    }

    /// 只在需要时设置光标；被别的 App 改掉了就再抢回来
    private func applyCursor(_ style: CursorStyle) {
        guard style != cursorStyle || NSCursor.current !== style.cursor else { return }
        cursorStyle = style
        style.cursor.set()
    }

    /// 退出 / 隐藏前把光标还原，免得留在别的窗口上是只小手
    func resetCursor() {
        cursorStyle = .arrow
        NSCursor.arrow.set()
    }

    func petMouseDown() {
        let point = eventPoint()
        guard !paused, !userHidden, !fullscreenHidden, !occluded else { return }
        guard petRect().insetBy(dx: -6, dy: -6).contains(point) else { return }
        downTime = CACurrentMediaTime()
        downPoint = point
        world.beginGrab(at: point)
        panel.ignoresMouseEvents = false
    }

    func petMouseDragged() {
        let point = eventPoint()
        guard world.state == .grabbed else { return }
        world.drag(to: point)
    }

    func petMouseUp() {
        let point = eventPoint()
        guard world.state == .grabbed else { return }
        // 按下就松开、几乎没拖动 = 点了一下，不是拎
        if CACurrentMediaTime() - downTime < 0.25 && hypot(point.x - downPoint.x, point.y - downPoint.y) < 5 {
            world.click()
        } else {
            world.endGrab()
        }
        panel.ignoresMouseEvents = !petRect().contains(point)
    }

    // MARK: 渲染

    private func applyVisuals() {
        layoutBox()
        rig.apply(PetAnimator.pose(for: world))

        let lift = max(0, world.position.y - world.groundY)
        let t = min(1, lift / 240)
        let scale = (1 - 0.42 * t) * (1 + 0.04 * (1 - t))
        let lying = world.state == .sleep
        shadowNode.position = SCNVector3(world.position.x + (lying ? world.facing * 32 : 0), world.groundY + 1.5, 1)
        shadowNode.scale = SCNVector3(scale * (lying ? 1.9 : 1), scale, scale)
        shadowNode.opacity = 1 - 0.75 * t
    }
}

// MARK: - 全屏检测

enum FrontmostAppWindow {

    /// 最前面的 App 有没有一个盖满整屏的窗口（即全屏模式）
    static func isFullscreen(on screen: NSScreen) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        if frontApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screenFrame = screen.frame
        for info in list {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == frontApp.processIdentifier else { continue }
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
            if width >= screenFrame.width - 4 && height >= screenFrame.height - 4 {
                return true
            }
        }
        return false
    }
}

extension FrontmostAppWindow {

    /// 最前面 App 的最前面那个普通窗口的顶边，换算成舞台坐标（左下原点，y 向上）。
    /// 只读窗口位置，不读标题和内容，不需要屏幕录制权限。
    static func topEdge(on screen: NSScreen, groundY: CGFloat) -> Platform? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        // CG 坐标原点在主屏左上角
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == frontApp.processIdentifier,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let b = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let x = (b["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (b["Y"] as? NSNumber)?.doubleValue ?? 0
            let w = (b["Width"] as? NSNumber)?.doubleValue ?? 0
            let h = (b["Height"] as? NSNumber)?.doubleValue ?? 0
            guard w >= 100, h >= 60 else { continue }
            if w >= screen.frame.width - 4 && h >= screen.frame.height - 4 { return nil }   // 全屏
            let top = CGFloat(mainHeight - y) - screen.frame.minY
            let x0 = CGFloat(x) - screen.frame.minX
            // 太低（贴着程序坞）或太高（顶着菜单栏）都不当平台
            guard top > groundY + 70, top < screen.frame.height - 30 - 92 else { return nil }
            let id = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            return Platform(id: id, x0: max(0, x0), x1: min(screen.frame.width, x0 + CGFloat(w)), y: top)
        }
        return nil
    }
}

/// 有没有声音在放：逐个进程看谁在往扬声器输出（macOS 14.4+，不需要权限，也听不到内容）。
/// 有些 App 开着就一直占着音频输出、其实没声音（实测 Blender 就是），放进忽略名单，
/// 否则 Pip 会一直跳舞。
enum SoundOutput {
    static let ignoredApps: Set<String> = [
        "Blender", "DaVinci Resolve", "Final Cut Pro", "iMovie", "Motion", "Compressor",
        "zoom.us", "Microsoft Teams", "腾讯会议", "TencentMeeting", "FaceTime", "Pip"
    ]

    static func isPlaying() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        for id in ids {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &running) == noErr, running != 0 else { continue }
            a.mSelector = kAudioProcessPropertyPID
            var pid: pid_t = 0
            s = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &pid) == noErr, pid != me else { continue }
            // 后台系统进程（没有 App 名字的）不算
            guard let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName else { continue }
            if ignoredApps.contains(name) { continue }
            return true
        }
        return false
    }
}

extension FrontmostAppWindow {

    /// 屏幕上所有普通窗口「露在外面」的顶边（被更前面的窗口挡住的那段去掉，取剩下最长的一段）。
    /// 只读位置，不读内容，免权限。
    static func allTopEdges(on screen: NSScreen, groundY: CGFloat) -> [Platform] {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        var inFront: [CGRect] = []          // CG 坐标（左上原点，y 向下）
        var result: [Platform] = []
        for info in list {                  // 列表是从前往后排的
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != me,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05,
                  let b = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            let r = CGRect(x: (b["X"] as? NSNumber)?.doubleValue ?? 0, y: (b["Y"] as? NSNumber)?.doubleValue ?? 0,
                           width: (b["Width"] as? NSNumber)?.doubleValue ?? 0, height: (b["Height"] as? NSNumber)?.doubleValue ?? 0)
            defer { inFront.append(r) }
            guard r.width >= 100, r.height >= 60 else { continue }
            let top = CGFloat(mainHeight) - r.minY - screen.frame.minY
            guard top > groundY + 50, top < screen.frame.height - 30 - 60 else { continue }
            // 顶边这条线上，被前面窗口盖住的区间扣掉
            var segs: [(CGFloat, CGFloat)] = [(r.minX, r.maxX)]
            for f in inFront where f.minY < r.minY + 1 && f.maxY > r.minY - 1 {
                segs = segs.flatMap { s -> [(CGFloat, CGFloat)] in
                    if f.maxX <= s.0 || f.minX >= s.1 { return [s] }
                    var out: [(CGFloat, CGFloat)] = []
                    if f.minX > s.0 { out.append((s.0, f.minX)) }
                    if f.maxX < s.1 { out.append((f.maxX, s.1)) }
                    return out
                }
            }
            guard let best = segs.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }), best.1 - best.0 >= 70 else { continue }
            let id = (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0
            let x0 = max(0, best.0 - screen.frame.minX), x1 = min(screen.frame.width, best.1 - screen.frame.minX)
            guard x1 - x0 >= 70 else { continue }
            result.append(Platform(id: id, x0: x0, x1: x1, y: top))
        }
        return result
    }
}
