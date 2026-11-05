import Foundation
import CoreGraphics

// MARK: - 状态

enum PetState: String {
    case idle
    case walk
    case grabbed
    case falling
    case landing

    /// 打印 / 自检用的中文名
    var displayName: String {
        switch self {
        case .idle: return "发呆"
        case .walk: return "走路"
        case .grabbed: return "被拎起"
        case .falling: return "下落"
        case .landing: return "落地"
        }
    }
}

// MARK: - 可复现的随机数（自检要跑出同样的结果）

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<1
    mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    mutating func range(_ lower: Double, _ upper: Double) -> CGFloat {
        CGFloat(lower + unit() * (upper - lower))
    }

    mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }
}

// MARK: - 世界（纯逻辑，不依赖 AppKit，可离屏跑）

/// 只负责「小人在屏幕坐标系里的位置、速度、状态」。
/// 坐标系：窗口左下角为原点，单位是点（point），y 向上。与 SCNView 的视图坐标 1:1 对应。
final class PetWorld {

    // 物理常量
    static let walkSpeed: CGFloat = 46          // 点/秒
    static let gravity: CGFloat = 2400          // 点/秒²
    static let airDrag: CGFloat = 0.9           // 每秒水平阻尼比例
    static let wallRestitution: CGFloat = 0.45  // 撞墙反弹系数
    static let ceilingRestitution: CGFloat = 0.3
    static let maxThrowSpeed: CGFloat = 2000    // 最大抛出速度，防止飞出屏幕
    static let landingDuration: CGFloat = 0.42  // 落地动作时长

    // 角色尺寸（点）
    let halfWidth: CGFloat = 33
    let characterHeight: CGFloat = 96

    // 环境
    private(set) var size: CGSize
    private(set) var groundY: CGFloat

    // 角色状态
    private(set) var position: CGPoint
    private(set) var velocity: CGVector = .zero
    private(set) var facing: CGFloat = 1         // 1 朝右，-1 朝左
    private(set) var state: PetState = .idle
    private(set) var time: CGFloat = 0
    private(set) var stateTime: CGFloat = 0
    private(set) var walkPhase: CGFloat = 0
    private(set) var grabVelocity: CGVector = .zero
    private(set) var landingImpact: CGFloat = 0

    // 内部
    private var grabOffset: CGVector = .zero
    private var dragTarget: CGPoint?
    private var wanderTimer: CGFloat = 0
    private var wanderDuration: CGFloat = 1.8
    private var rng: SeededRNG

    init(size: CGSize, groundY: CGFloat, seed: UInt64 = 0x5EED_2026) {
        self.size = size
        self.groundY = groundY
        self.rng = SeededRNG(seed: seed)
        self.position = CGPoint(x: size.width / 2, y: groundY)
    }

    // MARK: 边界

    var minX: CGFloat { halfWidth }
    var maxX: CGFloat { max(halfWidth * 2, size.width - halfWidth) }

    /// 移动中就要 30fps，发呆 10fps
    var isMoving: Bool {
        switch state {
        case .idle: return false
        case .walk, .grabbed, .falling, .landing: return true
        }
    }

    // MARK: 环境更新

    /// 屏幕尺寸 / 程序坞位置变化时调用
    func setGeometry(size: CGSize, groundY: CGFloat) {
        self.size = size
        self.groundY = groundY
        position.x = min(max(position.x, minX), maxX)
        switch state {
        case .idle, .walk, .landing:
            position.y = groundY
        case .grabbed, .falling:
            position.y = min(max(position.y, groundY), size.height)
        }
    }

    // MARK: 每帧更新

    func update(dt rawDt: CGFloat) {
        let dt = min(max(rawDt, 0), 0.1)
        guard dt > 0 else { return }

        time += dt
        stateTime += dt

        switch state {
        case .idle, .walk:
            updateWander(dt: dt)
        case .grabbed:
            updateGrabbed(dt: dt)
        case .falling:
            updateFalling(dt: dt)
        case .landing:
            position.y = groundY
            velocity = .zero
            if stateTime >= Self.landingDuration {
                beginWander()
            }
        }
    }

    // MARK: 闲逛

    private func beginWander() {
        state = .idle
        stateTime = 0
        wanderTimer = 0
        wanderDuration = rng.range(0.5, 1.2)
        velocity = .zero
        position.y = groundY
    }

    private func chooseWanderAction() {
        wanderTimer = 0
        stateTime = 0
        let shouldWalk = rng.chance(0.58)
        if shouldWalk {
            state = .walk
            wanderDuration = rng.range(0.9, 2.8)
        } else {
            state = .idle
            wanderDuration = rng.range(1.2, 3.2)
        }
        if rng.chance(0.7) {
            facing = rng.chance(0.5) ? -1 : 1
        }
    }

    private func updateWander(dt: CGFloat) {
        wanderTimer += dt
        if wanderTimer >= wanderDuration {
            chooseWanderAction()
        }

        if state == .walk {
            position.x += facing * Self.walkSpeed * dt
            walkPhase += dt * 8.6
            if position.x <= minX {
                position.x = minX
                facing = 1
            } else if position.x >= maxX {
                position.x = maxX
                facing = -1
            }
        }

        position.y = groundY
        velocity = .zero
    }

    // MARK: 拎起 / 拖拽 / 松手

    func beginGrab(at point: CGPoint) {
        guard state != .grabbed else { return }
        state = .grabbed
        stateTime = 0
        velocity = .zero
        grabVelocity = .zero
        dragTarget = point
        // 记录抓取点和脚的相对位置，保证拎着头时脚自然下垂
        grabOffset = CGVector(dx: position.x - point.x, dy: position.y - point.y)
    }

    /// 设置当前鼠标位置，真正的移动在 update 里按 dt 处理
    func drag(to point: CGPoint) {
        guard state == .grabbed else { return }
        dragTarget = point
    }

    private func updateGrabbed(dt: CGFloat) {
        guard let target = dragTarget else { return }

        let desiredX = min(max(target.x + grabOffset.dx, minX), maxX)
        let desiredY = min(max(target.y + grabOffset.dy, groundY), size.height - characterHeight * 0.6)
        let desired = CGPoint(x: desiredX, y: desiredY)

        let dx = desired.x - position.x
        let dy = desired.y - position.y
        // 用这一帧的实际位移估算抛出手感
        let instant = CGVector(dx: dx / dt, dy: dy / dt)
        grabVelocity = CGVector(
            dx: grabVelocity.dx * 0.6 + instant.dx * 0.4,
            dy: grabVelocity.dy * 0.6 + instant.dy * 0.4
        )
        position = desired
    }

    func endGrab() {
        guard state == .grabbed else { return }
        dragTarget = nil

        var throwVelocity = grabVelocity
        let speed = hypot(throwVelocity.dx, throwVelocity.dy)
        if speed > Self.maxThrowSpeed {
            let scale = Self.maxThrowSpeed / speed
            throwVelocity = CGVector(dx: throwVelocity.dx * scale, dy: throwVelocity.dy * scale)
        }
        velocity = throwVelocity
        grabVelocity = .zero

        state = .falling
        stateTime = 0
    }

    // MARK: 下落

    private func updateFalling(dt: CGFloat) {
        velocity.dy -= Self.gravity * dt
        velocity.dx *= max(0, 1 - Self.airDrag * dt)

        position.x += velocity.dx * dt
        position.y += velocity.dy * dt

        // 左右边缘反弹
        if position.x < minX {
            position.x = minX
            velocity.dx = abs(velocity.dx) * Self.wallRestitution
        } else if position.x > maxX {
            position.x = maxX
            velocity.dx = -abs(velocity.dx) * Self.wallRestitution
        }

        // 顶部（鼠标甩太高）也弹一下，别飞出屏幕
        let ceiling = size.height - 4
        if position.y > ceiling {
            position.y = ceiling
            velocity.dy = -abs(velocity.dy) * Self.ceilingRestitution
        }

        // 落地
        if position.y <= groundY && velocity.dy <= 0 {
            let impact = abs(velocity.dy)
            position.y = groundY
            velocity = .zero
            if impact > 140 {
                landingImpact = min(1, impact / 1400)
                state = .landing
                stateTime = 0
            } else {
                beginWander()
            }
        }
    }

    // MARK: 仅供截图工具使用：直接把世界摆成某个状态

    func preview(state newState: PetState,
                 time newTime: CGFloat,
                 feet: CGPoint? = nil,
                 walkPhase newPhase: CGFloat = 0,
                 stateTime newStateTime: CGFloat = 0,
                 velocity newVelocity: CGVector = .zero,
                 grabVelocity newGrabVelocity: CGVector = .zero) {
        state = newState
        time = newTime
        walkPhase = newPhase
        stateTime = newStateTime
        velocity = newVelocity
        grabVelocity = newGrabVelocity
        if let feet { position = feet }
    }

    // MARK: 给自检用的只读快照

    struct Snapshot {
        var time: CGFloat
        var state: PetState
        var position: CGPoint
        var velocity: CGVector
    }

    var snapshot: Snapshot {
        Snapshot(time: time, state: state, position: position, velocity: velocity)
    }
}
