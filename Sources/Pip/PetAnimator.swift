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
            pose.legLeft = s * 0.55
            pose.legRight = -s * 0.55
            pose.armLeft = -s * 0.5
            pose.armRight = s * 0.5
            pose.bob = abs(s2) * 2.4
            pose.bodyLean = 0.07
            pose.headTilt = s * 0.03
            pose.squashY = 1 + abs(s2) * 0.02
            pose.blink = blink(t)

        case .grabbed:
            let flail = sin(t * 15)
            let flail2 = sin(t * 12.5 + 1.1)
            pose.armLeft = 0.7 + flail * 0.75
            pose.armRight = -0.7 - flail * 0.75
            pose.legLeft = flail2 * 0.55
            pose.legRight = -flail2 * 0.55
            pose.headTilt = sin(t * 6.5) * 0.1
            pose.headYaw = sin(t * 3.1) * 0.12
            pose.bodyLean = clamp(-world.grabVelocity.dx * 0.00025, -0.28, 0.28)
            pose.squashY = 1.02
            pose.blink = 0.15

        case .falling:
            let speed = hypot(world.velocity.dx, world.velocity.dy)
            pose.squashY = 1 + min(0.12, speed / 12000)
            pose.armLeft = 1.15 + sin(t * 9) * 0.12
            pose.armRight = -1.15 - sin(t * 9) * 0.12
            pose.legLeft = 0.35
            pose.legRight = -0.35
            pose.headPitch = clamp(-world.velocity.dy * 0.00012, -0.15, 0.15)
            pose.headTilt = 0.05

        case .landing:
            let u = min(1, world.stateTime / PetWorld.landingDuration)
            // 压扁 → 回弹超调 → 归位
            let squash: CGFloat
            if u < 0.3 {
                squash = lerp(1.0, 0.72, u / 0.3)
            } else if u < 0.65 {
                squash = lerp(0.72, 1.07, (u - 0.3) / 0.35)
            } else {
                squash = lerp(1.07, 1.0, (u - 0.65) / 0.35)
            }
            pose.squashY = squash
            pose.armLeft = 0.45 * (1 - u)
            pose.armRight = -0.45 * (1 - u)
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

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func clamp(_ v: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(v, low), high)
    }
}
