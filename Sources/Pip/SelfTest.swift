import Foundation
import CoreGraphics

// MARK: - 离屏自检：不开窗口，模拟 10 秒状态机

enum SelfTest {

    private struct ThrowPlan {
        let grabStep: Int
        let releaseStep: Int
        let dragX: CGFloat
        let dragY: CGFloat
        let label: String
    }

    static func run() -> Bool {
        let size = CGSize(width: 1600, height: 900)
        let groundY: CGFloat = 60
        let world = PetWorld(size: size, groundY: groundY, seed: 20261105)
        let dt: CGFloat = 1.0 / 60.0
        let totalSteps = 600   // 10 秒

        // 两次抓抛：第一次往上抬+往右甩；第二次往左狠甩，撞左墙反弹
        let plans = [
            ThrowPlan(grabStep: 120, releaseStep: 192, dragX: 250, dragY: 300, label: "往上抬+往右甩"),
            ThrowPlan(grabStep: 360, releaseStep: 390, dragX: -900, dragY: 320, label: "往左狠甩（撞墙）")
        ]

        print("Pip 自检 —— 模拟 10 秒（两次拎起 + 抛出）")
        print("屏幕 1600x900，地面 y=60，起始位置 (\(num(world.position.x)), \(num(world.position.y)))")
        print("")

        var activePlan: ThrowPlan?
        var anchor = CGPoint.zero
        var previousState = world.state
        var previousVelocityX: CGFloat = 0
        var seenStates: Set<String> = [world.state.rawValue]
        var violations: [String] = []
        var maxLift: CGFloat = 0
        var landedAtLeastOnce = false
        var sawWallBounce = false

        for step in 0...totalSteps {
            let t = CGFloat(step) * dt

            // —— 脚本化输入 ——
            if let plan = plans.first(where: { $0.grabStep == step }) {
                anchor = CGPoint(x: world.position.x, y: world.position.y + 70)
                world.beginGrab(at: anchor)
                activePlan = plan
                print("  t=\(pad(t))s  [输入] 抓住头部附近 (\(num(anchor.x)), \(num(anchor.y)))，\(plan.label)")
            }
            if let plan = activePlan, step > plan.grabStep, step < plan.releaseStep {
                let u = CGFloat(step - plan.grabStep) / CGFloat(plan.releaseStep - plan.grabStep)
                let cursor = CGPoint(x: anchor.x + plan.dragX * u,
                                     y: anchor.y + plan.dragY * (sin(u * .pi) * 0.7 + u * 0.6))
                world.drag(to: cursor)
            }
            if let plan = activePlan, step == plan.releaseStep {
                world.endGrab()
                print("  t=\(pad(t))s  [输入] 松手，抛出速度 (\(num(world.velocity.dx)), \(num(world.velocity.dy)))")
                activePlan = nil
            }

            world.update(dt: dt)

            // —— 不变量 ——
            let p = world.position
            if p.y < groundY - 0.01 {
                violations.append("t=\(num(t)) 穿地：y=\(num(p.y)) < 地面 \(num(groundY))")
            }
            if p.x < -0.01 || p.x > size.width + 0.01 {
                violations.append("t=\(num(t)) 横向出屏：x=\(num(p.x))")
            }
            if p.y > size.height + 0.01 {
                violations.append("t=\(num(t)) 纵向出屏：y=\(num(p.y))")
            }
            maxLift = max(maxLift, p.y - groundY)

            // —— 撞墙反弹检测 ——
            if world.state == .falling {
                if previousVelocityX < -40 && world.velocity.dx > 20 {
                    sawWallBounce = true
                    print("  t=\(pad(t))s  [检查] 左墙反弹：vx \(num(previousVelocityX)) → \(num(world.velocity.dx))，x=\(num(p.x))")
                }
                if previousVelocityX > 40 && world.velocity.dx < -20 {
                    sawWallBounce = true
                    print("  t=\(pad(t))s  [检查] 右墙反弹：vx \(num(previousVelocityX)) → \(num(world.velocity.dx))，x=\(num(p.x))")
                }
            }
            previousVelocityX = world.velocity.dx

            // —— 状态变化 ——
            if world.state != previousState {
                print("  t=\(pad(t))s  \(previousState.displayName) → \(world.state.displayName)"
                      + "    位置=(\(pad(p.x)), \(pad(p.y)))")
                if world.state == .landing { landedAtLeastOnce = true }
                previousState = world.state
                seenStates.insert(world.state.rawValue)
            }

            // —— 每 0.5 秒一行 ——
            if step % 30 == 0 {
                print("  t=\(pad(t))s  [\(world.state.displayName)]"
                      + " 位置=(\(pad(p.x)), \(pad(p.y)))"
                      + " 速度=(\(pad(world.velocity.dx)), \(pad(world.velocity.dy)))")
            }
        }

        print("")

        var problems: [String] = []
        if let first = violations.first {
            problems.append("违反不变量：\(first)（共 \(violations.count) 次）")
        }
        if !seenStates.contains("grabbed") { problems.append("没有进入「被拎起」状态") }
        if !seenStates.contains("falling") { problems.append("没有进入「下落」状态") }
        if !landedAtLeastOnce { problems.append("没有播放过「落地」动作") }
        if !sawWallBounce { problems.append("没有观察到撞墙反弹") }
        if !(world.state == .idle || world.state == .walk) {
            problems.append("10 秒结束时没有回到闲逛，实际停在「\(world.state.displayName)」")
        }
        if maxLift < 80 {
            problems.append("没有被抬起来（最大离地 \(Int(maxLift)) 点）")
        }

        print("检查项：")
        print("  [\(violations.isEmpty ? "通过" : "失败")] 全程没有穿过地面 / 没有出屏（601 步采样）")
        print("  [\(seenStates.contains("grabbed") ? "通过" : "失败")] 进入「被拎起」")
        print("  [\(seenStates.contains("falling") ? "通过" : "失败")] 松手后进入「下落」")
        print("  [\(sawWallBounce ? "通过" : "失败")] 撞到屏幕左右边缘会反弹")
        print("  [\(landedAtLeastOnce ? "通过" : "失败")] 落地播放了落地动作（最大离地 \(Int(maxLift)) 点）")
        print("  [\((world.state == .idle || world.state == .walk) ? "通过" : "失败")] 最后回到闲逛（当前「\(world.state.displayName)」）")
        print("")

        if problems.isEmpty {
            print("PASS")
            return true
        } else {
            for problem in problems { print("✗ \(problem)") }
            print("FAIL")
            return false
        }
    }

    // MARK: 格式化

    private static func num(_ v: CGFloat) -> String {
        String(format: "%.1f", Double(v))
    }

    private static func pad(_ v: CGFloat) -> String {
        String(format: "%6.1f", Double(v))
    }
}
