import Foundation
import CoreGraphics

/// 把「世界状态」翻译成「一帧姿势」。纯函数，不碰 SceneKit，方便自检和以后换模型。
enum PetAnimator {

    static func pose(for world: PetWorld) -> Pose {
        var pose = Pose()
        pose.feet = world.position
        pose.facing = world.facing
        let t = world.time

        switch world.state {
        case .idle:
            let breathe = sin(t * 1.7)
            pose.squashY = 1 + breathe * 0.012
            pose.bob = breathe * 0.9
            pose.headTilt = sin(t * 0.6) * 0.05
            pose.headYaw = sin(t * 0.37) * 0.22
            pose.armLeft = 0.06 + breathe * 0.03
            pose.armRight = -0.06 - breathe * 0.03
            pose.blink = blink(t)

        case .walk:
            let s = sin(world.walkPhase)
            let s2 = sin(world.walkPhase * 2)
            // 侧身朝行进方向，正面相机才看得见腿一前一后；身体左右摇摆约 8 度，抬起的那只脚离地
            // 脸贴着身体曲面，可以放心侧身
            pose.bodyYaw = 0.42
            pose.legLeft = s * 0.6
            pose.legRight = -s * 0.6
            pose.liftLeft = max(0, s) * 3.2
            pose.liftRight = max(0, -s) * 3.2
            pose.armLeft = 0.15 - s * 0.45
            pose.armRight = -0.15 + s * 0.45
            pose.bob = abs(s2) * 2.6
            pose.bodyLean = 0.05 + s * 0.14
            pose.headTilt = -s * 0.06
            pose.squashY = 1 - abs(s2) * 0.035
            pose.blink = blink(t)

        case .grabbed:
            // 被揪住头顶：双爪举高乱挥，身体被拉长，两腿软软下垂、往外乱蹬，整个人轻轻晃
            let flail = sin(t * 13)
            let kickL = sin(t * 9.5)
            let kickR = sin(t * 9.5 + 2.2)
            pose.armLeft = 2.35 + flail * 0.22
            pose.armRight = 2.35 - flail * 0.22
            pose.legSideLeft = 0.22 + kickL * 0.32
            pose.legSideRight = 0.22 + kickR * 0.32
            pose.legLeft = kickR * 0.25
            pose.legRight = kickL * 0.25
            pose.headTilt = sin(t * 4.2) * 0.08
            pose.headYaw = sin(t * 2.3) * 0.1
            pose.bodyLean = clamp(-world.grabVelocity.dx * 0.00025, -0.28, 0.28) + sin(t * 2.6) * 0.06
            pose.squashY = 1.12
            pose.blink = 0.15

        case .falling where world.startled:
            // 被点了一下：吓一跳，眼睛瞪大，两爪往上一扬
            pose.armLeft = 2.0
            pose.armRight = 2.0
            pose.eyeScale = 1.35
            pose.squashY = 1.06
            pose.legSideLeft = 0.25
            pose.legSideRight = 0.25

        case .falling:
            let speed = hypot(world.velocity.dx, world.velocity.dy)
            pose.squashY = 1 + min(0.12, speed / 12000)
            // 两只爪都往上扬（左右角度同号才是对称的，之前写反了）
            pose.armLeft = 1.5 + sin(t * 9) * 0.12
            pose.armRight = 1.5 - sin(t * 9) * 0.12
            pose.legLeft = 0.35
            pose.legRight = -0.35
            pose.headPitch = clamp(-world.velocity.dy * 0.00012, -0.15, 0.15)
            pose.headTilt = 0.05

        case .landing:
            let u = min(1, world.stateTime / PetWorld.landingDuration)
            // 压扁 → 回弹超调 → 归位
            let squash: CGFloat
            // 软绵绵：压扁约 25% → 回弹超调 → 再小弹一下 → 归位
            if u < 0.22 {
                squash = lerp(1.0, 0.75, ease(u / 0.22))
            } else if u < 0.5 {
                squash = lerp(0.75, 1.09, ease((u - 0.22) / 0.28))
            } else if u < 0.72 {
                squash = lerp(1.09, 0.96, ease((u - 0.5) / 0.22))
            } else {
                squash = lerp(0.96, 1.0, ease((u - 0.72) / 0.28))
            }
            pose.squashY = squash
            pose.armLeft = 0.6 * (1 - u)
            pose.armRight = 0.6 * (1 - u)
            pose.legLeft = 0.2 * (1 - u)
            pose.legRight = -0.2 * (1 - u)

        case .sleep:
            // 侧躺在地上睡：整个身子朝面向的一侧倒下（脸仍朝着屏幕），肚子随呼吸一起一伏，冒 z
            let breathe = sin(t * 1.4)
            pose.bodyLean = sleepLean
            pose.bob = sleepLift + breathe * 0.6
            pose.squashY = 0.97 + breathe * 0.012
            pose.armLeft = 0.15
            pose.armRight = 0.15
            pose.legLeft = 0.15
            pose.legRight = -0.1
            pose.blink = 1
            pose.zzz = t

        case .wake:
            // 先从地上坐起来，再伸懒腰：双爪慢慢举高、身体拉长，再落回来
            let u = min(1, world.stateTime / PetWorld.wakeDuration)
            let rise = ease(min(1, u / 0.35))
            pose.bodyLean = sleepLean * (1 - rise)
            pose.bob = sleepLift * (1 - rise)
            let v = max(0, (u - 0.35) / 0.65)
            let reach = sin(v * .pi)
            pose.armLeft = 0.3 + reach * 2.4
            pose.armRight = 0.3 + reach * 2.4
            pose.squashY = 0.9 + reach * 0.2
            pose.headPitch = -reach * 0.15
            pose.blink = max(0, 1 - u * 1.6) * 0.8
            pose.happyEyes = reach * 0.6

        case .petted:
            // 眯眼享受，脸红，身体跟着轻轻左右蹭
            let sway = sin(t * 3.2)
            pose.happyEyes = 1
            pose.blush = 1.9
            pose.bodyLean = sway * 0.1
            pose.headTilt = sway * 0.12 + 0.05
            pose.squashY = 0.97 + abs(sin(t * 3.2)) * 0.03
            pose.armLeft = 0.25 + sway * 0.1
            pose.armRight = 0.25 - sway * 0.1

        case .dance:
            // 约 112 拍/分：每拍一次上下颠，左右交替扭，两爪轮流举
            let beat = t * (112.0 / 60.0) * 2 * .pi
            let b = sin(beat)
            let half = sin(beat / 2)
            pose.bob = abs(b) * 3.2
            pose.squashY = 1 - abs(b) * 0.05
            pose.bodyLean = half * 0.16
            pose.headTilt = -half * 0.14
            pose.armLeft = 0.4 + max(0, half) * 1.9
            pose.armRight = 0.4 + max(0, -half) * 1.9
            pose.liftLeft = max(0, half) * 2.4
            pose.liftRight = max(0, -half) * 2.4
            pose.happyEyes = 0.8
            pose.blush = 1.3

        case .sign:
            // 双爪举着牌子，轻轻晃
            let sway = sin(t * 2.4)
            pose.armLeft = 2.55
            pose.armRight = 2.55
            pose.bodyLean = sway * 0.05
            pose.headTilt = sway * 0.06
            pose.sign = world.signText
            pose.blink = blink(t)

        case .perch:
            // 坐在窗口顶边上，两条小腿悬在边外前后晃
            let swing = sin(t * 3.0)
            // 屁股坐在边上（身体往下沉），两条腿垂在窗口正面前后晃（正面相机看得见）
            pose.squashY = 0.92
            pose.bob = -11
            pose.legLeft = 0.25 + swing * 0.45
            pose.legRight = 0.25 - swing * 0.45
            pose.armLeft = 0.2
            pose.armRight = 0.2
            pose.headTilt = sin(t * 0.8) * 0.06
            pose.headYaw = sin(t * 0.5) * 0.2
            pose.blink = blink(t)
        }

        return pose
    }

    // MARK: 小工具

    /// 每 4.7 秒眨一次眼，持续 0.16 秒
    private static func blink(_ t: CGFloat) -> CGFloat {
        let period: CGFloat = 4.7
        let window: CGFloat = 0.16
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase > period - window else { return 0 }
        return sin((phase - (period - window)) / window * .pi)
    }

    /// 躺下：身体转约 85°；脚底是转轴，要把身体抬起约一个身体半径才贴着地面
    static let sleepLean: CGFloat = 1.48
    static let sleepLift: CGFloat = 30

    private static func ease(_ x: CGFloat) -> CGFloat {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(v, low), high)
    }
}
