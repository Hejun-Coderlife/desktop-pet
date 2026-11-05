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
            // 脸是贴在身前的平面软片，侧转太多会戳出轮廓：身体转 0.24，头再往回扭一点，脸基本朝前
            pose.bodyYaw = 0.24
            pose.headYaw = -0.12
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
