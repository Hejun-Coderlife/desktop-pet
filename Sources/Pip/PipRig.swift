import AppKit
import SceneKit

// MARK: - 配色（柔和、无红帽子）

enum PipPalette {
    static let body      = NSColor.hex(0xA8E0CE)   // 薄荷绿
    static let limb      = NSColor.hex(0x97D6C1)   // 稍深的薄荷
    static let belly     = NSColor.hex(0xFFF6E9)   // 奶油白
    static let cheek     = NSColor.hex(0xF7B6A6)   // 蜜桃粉
    static let eyeWhite  = NSColor.hex(0xFFFFFF)
    static let pupil     = NSColor.hex(0x2E4B46)   // 深墨绿
    static let mouth     = NSColor.hex(0x5E7F77)
    static let leaf      = NSColor.hex(0x74C4A2)
    static let stem      = NSColor.hex(0x8CCFB3)
}

extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                green: CGFloat((value >> 8) & 0xFF) / 255.0,
                blue: CGFloat(value & 0xFF) / 255.0,
                alpha: alpha)
    }
}

// MARK: - 用基础形体拼出来的 Q 版小人「Pip」

/// 结构：
/// root（脚底锚点，位置 = 屏幕坐标）
///  └ squash（压扁/拉伸）
///     └ bodyGroup（上下起伏、前倾）
///        ├ 身体、肚皮
///        ├ armPivotL / armPivotR（肩关节）
///        ├ legPivotL / legPivotR（髋关节）
///        └ headPivot（颈关节）→ headGroup → 头、耳朵、眼睛、腮红、嘴、小芽
final class PipRig: PetRig {

    let root = SCNNode()
    let pixelHeight: CGFloat = 96

    private let baseScale: CGFloat = 0.9     // 角色原始高度 104 → 实际约 94 点

    private let squashNode = SCNNode()
    private let bodyGroup = SCNNode()
    private let headPivot = SCNNode()
    private let headGroup = SCNNode()
    private let eyeGroupL = SCNNode()
    private let eyeGroupR = SCNNode()
    private let armPivotL = SCNNode()
    private let armPivotR = SCNNode()
    private let legPivotL = SCNNode()
    private let legPivotR = SCNNode()

    var node: SCNNode { root }

    init() {
        build()
    }

    // MARK: 组装

    private func build() {
        root.name = "pip.root"
        root.addChildNode(squashNode)
        squashNode.addChildNode(bodyGroup)

        // 身体
        let body = sphereNode(radius: 21, color: PipPalette.body)
        body.scale = SCNVector3(1.0, 1.04, 0.88)
        body.position = SCNVector3(0, 42, 0)
        bodyGroup.addChildNode(body)

        // 肚皮
        let belly = sphereNode(radius: 14.5, color: PipPalette.belly)
        belly.scale = SCNVector3(1.02, 1.08, 0.42)
        belly.position = SCNVector3(0, 37, 15.0)
        bodyGroup.addChildNode(belly)

        // 腿
        buildLeg(pivot: legPivotL, x: -9.5)
        buildLeg(pivot: legPivotR, x: 9.5)

        // 手
        buildArm(pivot: armPivotL, x: -19.5, sign: -1)
        buildArm(pivot: armPivotR, x: 19.5, sign: 1)

        // 头
        buildHead()
    }

    private func buildLeg(pivot: SCNNode, x: CGFloat) {
        pivot.position = SCNVector3(x, 25, 0)
        bodyGroup.addChildNode(pivot)

        // 胶囊顶进身体里，往下伸到脚踝，避免看起来断开
        let leg = capsuleNode(radius: 5.4, height: 16, color: PipPalette.limb)
        leg.position = SCNVector3(0, -10, 0)
        pivot.addChildNode(leg)

        let foot = sphereNode(radius: 5.8, color: PipPalette.limb)
        foot.scale = SCNVector3(1.0, 0.58, 1.3)
        foot.position = SCNVector3(0, -21.6, 1.8)
        pivot.addChildNode(foot)
    }

    private func buildArm(pivot: SCNNode, x: CGFloat, sign: CGFloat) {
        pivot.position = SCNVector3(x, 48, 0)
        bodyGroup.addChildNode(pivot)

        let arm = capsuleNode(radius: 4.4, height: 15, color: PipPalette.limb)
        arm.position = SCNVector3(sign * 2.4, -9.5, 0)
        pivot.addChildNode(arm)

        let hand = sphereNode(radius: 4.9, color: PipPalette.limb)
        hand.position = SCNVector3(sign * 3.2, -16.5, 0)
        pivot.addChildNode(hand)
    }

    private func buildHead() {
        headPivot.position = SCNVector3(0, 56, 0)
        bodyGroup.addChildNode(headPivot)
        headPivot.addChildNode(headGroup)

        // 头（整体中心 y≈69）
        let head = sphereNode(radius: 23, color: PipPalette.body)
        head.scale = SCNVector3(1.0, 0.97, 0.95)
        head.position = SCNVector3(0, 13, 0)
        headGroup.addChildNode(head)

        // 耳朵
        for sign in [CGFloat(-1), CGFloat(1)] {
            let ear = sphereNode(radius: 6.5, color: PipPalette.body)
            ear.scale = SCNVector3(1.0, 1.3, 0.62)
            ear.position = SCNVector3(sign * 16.5, 28, -1.0)
            headGroup.addChildNode(ear)
        }

        // 眼睛（白眼球 + 瞳孔 + 高光，打组方便眨眼缩放）
        for (group, sign) in [(eyeGroupL, CGFloat(-1)), (eyeGroupR, CGFloat(1))] {
            group.position = SCNVector3(sign * 9, 14.5, 20.0)

            let white = sphereNode(radius: 6.3, color: PipPalette.eyeWhite)
            white.scale = SCNVector3(1.0, 1.15, 0.6)
            group.addChildNode(white)

            let pupil = sphereNode(radius: 3.5, color: PipPalette.pupil)
            pupil.scale = SCNVector3(1.0, 1.0, 0.45)
            pupil.position = SCNVector3(0, -0.3, 2.5)
            group.addChildNode(pupil)

            let shine = sphereNode(radius: 1.5, color: PipPalette.eyeWhite)
            shine.position = SCNVector3(sign * 1.6, 1.9, 3.6)
            group.addChildNode(shine)

            headGroup.addChildNode(group)
        }

        // 腮红
        for sign in [CGFloat(-1), CGFloat(1)] {
            let cheek = sphereNode(radius: 5, color: PipPalette.cheek.withAlphaComponent(0.9))
            cheek.scale = SCNVector3(1.25, 0.75, 0.4)
            cheek.position = SCNVector3(sign * 17.5, 5.5, 13.5)
            headGroup.addChildNode(cheek)
        }

        // 嘴
        let mouth = sphereNode(radius: 2.4, color: PipPalette.mouth)
        mouth.scale = SCNVector3(1.6, 0.5, 0.4)
        mouth.position = SCNVector3(0, 6.0, 20.8)
        headGroup.addChildNode(mouth)

        // 头顶小芽（原创标志）
        let stem = cylinderNode(radius: 1.5, height: 9, color: PipPalette.stem)
        stem.position = SCNVector3(0, 41, 0)
        headGroup.addChildNode(stem)

        let leafLeft = sphereNode(radius: 5, color: PipPalette.leaf)
        leafLeft.scale = SCNVector3(1.55, 0.42, 0.75)
        leafLeft.position = SCNVector3(-5.8, 45.5, 0)
        leafLeft.eulerAngles = SCNVector3(0, 0, 0.55)
        headGroup.addChildNode(leafLeft)

        let leafRight = sphereNode(radius: 5, color: PipPalette.leaf)
        leafRight.scale = SCNVector3(1.55, 0.42, 0.75)
        leafRight.position = SCNVector3(5.8, 45.5, 0)
        leafRight.eulerAngles = SCNVector3(0, 0, -0.55)
        headGroup.addChildNode(leafRight)
    }

    // MARK: 应用姿势

    func apply(_ pose: Pose) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true

        root.position = SCNVector3(pose.feet.x, pose.feet.y, 0)
        // facing 用 x 轴镜像；镜像时法线会翻，SceneKit 会自动处理
        root.scale = SCNVector3(baseScale * pose.facing, baseScale, baseScale)

        let sy = max(0.35, pose.squashY)
        let sxz = 1.0 / sqrt(sy)
        squashNode.scale = SCNVector3(sxz, sy, sxz)

        bodyGroup.position = SCNVector3(0, pose.bob, 0)
        bodyGroup.eulerAngles = SCNVector3(0, 0, -pose.bodyLean)

        headPivot.eulerAngles = SCNVector3(pose.headPitch, pose.headYaw, pose.headTilt)

        armPivotL.eulerAngles = SCNVector3(0, 0, -pose.armLeft)
        armPivotR.eulerAngles = SCNVector3(0, 0, pose.armRight)

        legPivotL.eulerAngles = SCNVector3(pose.legLeft, 0, 0)
        legPivotR.eulerAngles = SCNVector3(pose.legRight, 0, 0)

        let eyeScale = SCNVector3(1, max(0.08, 1 - pose.blink * 0.95), 1)
        eyeGroupL.scale = eyeScale
        eyeGroupR.scale = eyeScale

        SCNTransaction.commit()
    }

    // MARK: 几何工具

    private func material(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = false
        return m
    }

    private func sphereNode(radius: CGFloat, color: NSColor) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 64
        sphere.materials = [material(color)]
        return SCNNode(geometry: sphere)
    }

    private func capsuleNode(radius: CGFloat, height: CGFloat, color: NSColor) -> SCNNode {
        let capsule = SCNCapsule(capRadius: radius, height: height)
        capsule.radialSegmentCount = 40
        capsule.capSegmentCount = 16
        capsule.materials = [material(color)]
        return SCNNode(geometry: capsule)
    }

    private func cylinderNode(radius: CGFloat, height: CGFloat, color: NSColor) -> SCNNode {
        let cylinder = SCNCylinder(radius: radius, height: height)
        cylinder.radialSegmentCount = 24
        cylinder.materials = [material(color)]
        return SCNNode(geometry: cylinder)
    }
}
