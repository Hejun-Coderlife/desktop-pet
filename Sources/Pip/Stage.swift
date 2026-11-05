import AppKit
import SceneKit

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
        stage?.petMouseDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        stage?.petMouseDragged(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        stage?.petMouseUp(at: convert(event.locationInWindow, from: nil))
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

        sceneView = PetSceneView(frame: CGRect(origin: .zero, size: frame.size), options: nil)
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

        panel = PetPanel(contentRect: frame,
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
        panel.setFrame(frame, display: true)

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
            return
        }

        sceneView.isPlaying = true
        updateMouse(dt: dt)
        world.update(dt: dt)
        applyVisuals()
        updateFrameRate()
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
            panel.setFrame(frame, display: true)
            sceneView.frame = CGRect(origin: .zero, size: frame.size)
            world.setGeometry(size: frame.size, groundY: groundY)
            updateCamera(viewportSize: frame.size)
        } else if abs(groundY - world.groundY) > 0.5 {
            // 程序坞隐藏 / 换边 / 改大小
            world.setGeometry(size: frame.size, groundY: groundY)
        }

        occluded = panel.isVisible && !panel.occlusionState.contains(.visible)

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

    private func eventPoint() -> CGPoint {
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        return sceneView.convert(windowPoint, from: nil)
    }

    /// 小人的点击区域（窗口/视图坐标，1:1 点）
    private func petRect() -> CGRect {
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
                return
            }
            panel.ignoresMouseEvents = false
            world.drag(to: point)
            return
        }

        let inside = petRect().contains(point)
        let shouldIgnore = !inside
        if panel.ignoresMouseEvents != shouldIgnore {
            panel.ignoresMouseEvents = shouldIgnore
        }
    }

    func petMouseDown(at point: CGPoint) {
        guard !paused, !userHidden, !fullscreenHidden, !occluded else { return }
        guard petRect().insetBy(dx: -6, dy: -6).contains(point) else { return }
        world.beginGrab(at: point)
        panel.ignoresMouseEvents = false
    }

    func petMouseDragged(at point: CGPoint) {
        guard world.state == .grabbed else { return }
        world.drag(to: point)
    }

    func petMouseUp(at point: CGPoint) {
        guard world.state == .grabbed else { return }
        world.endGrab()
        panel.ignoresMouseEvents = !petRect().contains(point)
    }

    // MARK: 渲染

    private func applyVisuals() {
        rig.apply(PetAnimator.pose(for: world))

        let lift = max(0, world.position.y - world.groundY)
        let t = min(1, lift / 240)
        let scale = (1 - 0.42 * t) * (1 + 0.04 * (1 - t))
        shadowNode.position = SCNVector3(world.position.x, world.groundY + 1.5, 1)
        shadowNode.scale = SCNVector3(scale, scale, scale)
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
