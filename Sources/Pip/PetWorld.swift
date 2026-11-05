import Foundation
import CoreGraphics

// MARK: - 状态

enum PetState: String {
    case idle
    case walk
    case grabbed
    case falling
    case landing
    case sleep      // 打瞌睡（长时间没碰电脑）
    case wake       // 醒来伸懒腰
    case petted     // 被摸头，眯眼享受
    case dance      // 有声音在放，跟着摇
    case sign       // 举牌提醒
    case perch      // 坐在窗口顶上晃腿

    /// 打印 / 自检用的中文名
    var displayName: String {
        switch self {
        case .idle: return "发呆"
        case .walk: return "走路"
        case .grabbed: return "被拎起"
        case .falling: return "下落"
        case .landing: return "落地"
        case .sleep: return "睡觉"
        case .wake: return "伸懒腰"
        case .petted: return "被摸头"
        case .dance: return "跳舞"
        case .sign: return "举牌"
        case .perch: return "坐窗口上"
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

// MARK: - 可以站上去的平台（最前面窗口的顶边）

struct Platform: Equatable {
    var id: Int          // 窗口编号：同一个窗口挪动时跟着走，换了窗口就掉下来
    var x0: CGFloat
    var x1: CGFloat
    var y: CGFloat       // 顶边高度（窗口坐标，y 向上）
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
    static let sleepAfter: Double = 300          // 多少秒没碰鼠标键盘就睡
    static let wakeDuration: CGFloat = 1.6
    static let signDuration: CGFloat = 10

    // 角色尺寸（点）
    let halfWidth: CGFloat = 32
    let characterHeight: CGFloat = 92

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
    /// 被点了一下吓一跳（下落时用不同的姿势）
    private(set) var startled = false
    /// 被摸的舒服程度 0…1
    private(set) var happy: CGFloat = 0
    private(set) var signText: String?
    private(set) var platform: Platform?
    private(set) var onPlatform = false

    // 来自外界的输入（Stage 每帧写入）
    var idleSeconds: Double = 0
    var soundPlaying = false
    var climbEnabled = true
    /// 鼠标停在底部时想走过去的目标 x
    var attentionX: CGFloat?

    /// 当前脚下的高度：站在窗口上就是窗口顶边，否则是程序坞上沿
    var supportY: CGFloat { onPlatform ? (platform?.y ?? groundY) : groundY }
    private var supportMinX: CGFloat { onPlatform ? max(minX, (platform?.x0 ?? 0) + halfWidth * 0.6) : minX }
    private var supportMaxX: CGFloat { onPlatform ? min(maxX, (platform?.x1 ?? 0) - halfWidth * 0.6) : maxX }

    // 内部
    private var grabOffset: CGVector = .zero
    private var grabbedFrom: PetState = .idle
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
        case .idle, .sleep: return false
        default: return true
        }
    }

    // MARK: 环境更新

    /// 屏幕尺寸 / 程序坞位置变化时调用
    func setGeometry(size: CGSize, groundY: CGFloat) {
        self.size = size
        self.groundY = groundY
        position.x = min(max(position.x, minX), maxX)
        switch state {
        case .grabbed, .falling:
            position.y = min(max(position.y, groundY), size.height)
        default:
            position.y = supportY
        }
    }

    // MARK: 每帧更新

    func update(dt rawDt: CGFloat) {
        let dt = min(max(rawDt, 0), 0.1)
        guard dt > 0 else { return }

        time += dt
        stateTime += dt

        happy = max(0, happy - dt * 0.35)
        updateMoods()

        switch state {
        case .idle, .walk, .perch:
            updateWander(dt: dt)
        case .grabbed:
            updateGrabbed(dt: dt)
        case .falling:
            updateFalling(dt: dt)
        case .landing:
            position.y = supportY
            velocity = .zero
            if stateTime >= Self.landingDuration {
                beginWander()
            }
        case .sleep, .dance, .petted:
            position.y = supportY
            velocity = .zero
        case .wake:
            position.y = supportY
            if stateTime >= Self.wakeDuration { beginWander() }
        case .sign:
            position.y = supportY
            if stateTime >= Self.signDuration { signText = nil; beginWander() }
        }
    }

    /// 在「站着的」几个状态之间切换：被摸 > 举牌 > 跳舞 > 睡觉
    private func updateMoods() {
        let calm: Set<PetState> = [.idle, .walk, .perch, .dance, .sleep, .petted]
        guard calm.contains(state) else { return }

        if state == .sleep {
            if idleSeconds < 1 { enter(.wake) }
            return
        }
        if happy > 0.45 {
            if state != .petted { enter(.petted) }
            return
        }
        if state == .petted {
            if happy < 0.12 { beginWander() }
            return
        }
        if soundPlaying {
            if state != .dance { enter(.dance) }
            return
        }
        if state == .dance {
            beginWander()
            return
        }
        if idleSeconds > Self.sleepAfter {
            enter(.sleep)
        }
    }

    private func enter(_ newState: PetState) {
        state = newState
        stateTime = 0
        velocity = .zero
        position.y = supportY
    }

    // MARK: 外界触发的小事件

    /// 摸头：amount 是这一帧在它身上划过的距离折算
    func pet(amount: CGFloat) {
        guard state != .grabbed, state != .falling else { return }
        happy = min(1, happy + amount)
    }

    /// 点一下：吓一跳原地蹦起来（举着牌时点一下 = 收起牌子）
    func startle() {
        if state == .sign { signText = nil; beginWander(); return }
        guard state != .falling, state != .grabbed else { return }
        if state == .sleep { enter(.wake); return }
        state = .falling
        stateTime = 0
        startled = true
        velocity = CGVector(dx: 0, dy: 720)
        onPlatform = false   // 落回来时会重新踩上同一个平台
    }

    /// 按下马上松开 = 点了一下（不是拎）：举着牌就收牌，睡着就醒，否则吓一跳
    func click() {
        guard state == .grabbed else { return }
        dragTarget = nil
        grabVelocity = .zero
        switch grabbedFrom {
        case .sign:
            beginWanderKeepingHeight()
        case .sleep:
            state = .idle
            enter(.wake)
        default:
            state = .idle
            startle()
        }
    }

    private func beginWanderKeepingHeight() {
        // 被拎起那一下把 onPlatform 清了：如果脚下正好是平台，就当还站在上面
        if let p = platform, abs(position.y - p.y) < 2, position.x >= p.x0, position.x <= p.x1 { onPlatform = true }
        beginWander()
    }

    func showSign(_ text: String) {
        guard state != .grabbed, state != .falling else { return }
        signText = text
        enter(.sign)
    }

    /// 最前面窗口的顶边（nil = 没有合适的窗口）。同一个窗口挪了就跟着挪，换了/没了就掉下去。
    func setPlatform(_ newPlatform: Platform?) {
        let old = platform
        platform = climbEnabled ? newPlatform : nil
        guard onPlatform else { return }
        guard let p = platform, let o = old, p.id == o.id else { dropFromPlatform(); return }
        if p != o {
            position.x += p.x0 - o.x0
            let centerOK = position.x >= p.x0 && position.x <= p.x1
            if !centerOK { dropFromPlatform(); return }
            if state != .grabbed && state != .falling { position.y = p.y }
        }
    }

    private func dropFromPlatform() {
        onPlatform = false
        if state == .grabbed || state == .falling { return }
        state = .falling
        stateTime = 0
        velocity = CGVector(dx: facing * 60, dy: 0)
    }

    // MARK: 闲逛

    private func beginWander() {
        state = .idle
        stateTime = 0
        wanderTimer = 0
        wanderDuration = rng.range(0.5, 1.2)
        velocity = .zero
        startled = false
        position.y = supportY
    }

    private func chooseWanderAction() {
        wanderTimer = 0
        stateTime = 0
        // 站在窗口上：常常坐下来晃腿，偶尔自己跳下去
        if onPlatform {
            if rng.chance(0.12) { hopDown(); return }
            if rng.chance(0.5) {
                state = .perch
                wanderDuration = rng.range(3, 7)
                return
            }
        } else if let p = platform, attentionX == nil, rng.chance(0.22), jumpUp(to: p) {
            return
        }
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
        // 鼠标停在附近：慢慢走过去，到了就站着抬头看
        if let tx = attentionX, !onPlatform {
            let dx = tx - position.x
            if abs(dx) > 34 {
                state = .walk
                facing = dx > 0 ? 1 : -1
                wanderTimer = 0
                wanderDuration = 0.6
            } else if state == .walk {
                state = .idle
                wanderTimer = 0
                wanderDuration = 1.5
            }
        }

        wanderTimer += dt
        if wanderTimer >= wanderDuration {
            chooseWanderAction()
        }

        if state == .walk {
            let speed = attentionX != nil ? Self.walkSpeed * 1.25 : Self.walkSpeed
            position.x += facing * speed * dt
            walkPhase += dt * 8.6
            if position.x <= supportMinX {
                position.x = supportMinX
                facing = 1
            } else if position.x >= supportMaxX {
                position.x = supportMaxX
                facing = -1
            }
        }

        position.y = supportY
        velocity = .zero
    }

    // MARK: 跳上 / 跳下窗口

    /// 算一条抛物线从地面跳到窗口顶边；够不着（太高、太矮、窗口太窄）就不跳
    private func jumpUp(to p: Platform) -> Bool {
        let h = p.y - groundY
        guard h > 70, h < 760, p.x1 - p.x0 > halfWidth * 3 else { return false }
        let tx = min(max(position.x, p.x0 + halfWidth * 1.4), p.x1 - halfWidth * 1.4)
        guard abs(tx - position.x) < 420 else { return false }
        let rise = h + 46                                    // 比顶边再高一点，落下来时踩上去
        let vy = sqrt(2 * Self.gravity * rise)
        let tUp = vy / Self.gravity
        let tDown = sqrt(2 * 46 / Self.gravity)
        var vx = (tx - position.x) / (tUp + tDown)
        vx /= max(0.05, 1 - Self.airDrag * (tUp + tDown) / 2)   // 补偿空气阻尼
        facing = vx >= 0 ? 1 : -1
        state = .falling
        stateTime = 0
        velocity = CGVector(dx: vx, dy: vy)
        return true
    }

    private func hopDown() {
        onPlatform = false
        state = .falling
        stateTime = 0
        velocity = CGVector(dx: facing * 160, dy: 380)
    }

    // MARK: 拎起 / 拖拽 / 松手

    func beginGrab(at point: CGPoint) {
        guard state != .grabbed else { return }
        grabbedFrom = state
        onPlatform = false
        if state == .sign { signText = nil }
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
        let previousY = position.y
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

        // 踩到窗口顶边
        if let p = platform, velocity.dy <= 0, previousY >= p.y - 0.5, position.y <= p.y,
           position.x >= p.x0 + halfWidth * 0.4, position.x <= p.x1 - halfWidth * 0.4 {
            let impact = abs(velocity.dy)
            onPlatform = true
            position.y = p.y
            velocity = .zero
            startled = false
            if impact > 140 {
                landingImpact = min(1, impact / 1400)
                state = .landing
                stateTime = 0
            } else {
                beginWander()
            }
            return
        }

        // 落地
        if position.y <= groundY && velocity.dy <= 0 {
            onPlatform = false
            startled = false
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
                 grabVelocity newGrabVelocity: CGVector = .zero,
                 sign: String? = nil) {
        state = newState
        signText = sign
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
