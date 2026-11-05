import AppKit
import SceneKit

// MARK: - 配色（米白绒毛 + 奶油脸）

enum PipPalette {
    static let fur       = NSColor.hex(0xF4EEE4)   // 米白绒毛
    static let furDeep   = NSColor.hex(0xE7DCCC)   // 帽沿/手脚稍深
    static let face      = NSColor.hex(0xEFE2CE)   // 奶油色光滑脸
    static let cheek     = NSColor.hex(0xE9A99C)   // 腮红
    static let eye       = NSColor.hex(0x1A1917)   // 近黑
    static let shine     = NSColor.hex(0xFFFFFF)
    static let mouth     = NSColor.hex(0x3A3330)
}

extension NSColor {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
                green: CGFloat((value >> 8) & 0xFF) / 255.0,
                blue: CGFloat(value & 0xFF) / 255.0,
                alpha: alpha)
    }
}

// MARK: - Q 版绒毛小人「Pip」

/// 结构：
/// root（脚底锚点，位置 = 屏幕坐标）
///  └ squash（压扁/拉伸）
///     └ bodyGroup（上下起伏、前倾）
///        ├ 身体（绒毛）
///        ├ armPivotL / armPivotR（肩关节）
///        ├ legPivotL / legPivotR（髋关节）
///        └ headPivot（颈关节）→ headGroup
///             └ 兜帽 + 绒毛尖 + 光滑脸 + 帽沿绒毛圈 + 眼睛 + 腮红 + 细弧嘴
final class PipRig: PetRig {

    let root = SCNNode()
    let pixelHeight: CGFloat = 92

    private let baseScale: CGFloat = 1.0

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

    private lazy var furMaterial: SCNMaterial = makeFurMaterial(PipPalette.fur)

    var node: SCNNode { root }

    init() {
        build()
    }

    // MARK: 组装

    private func build() {
        root.name = "pip.root"
        root.addChildNode(squashNode)
        squashNode.addChildNode(bodyGroup)

        // 身体：一颗蛋（下宽上收），兜帽直接扣在上半身
        let body = sphereNode(radius: 25, material: furMaterial)
        body.scale = SCNVector3(1.04, 1.16, 0.92)
        body.position = SCNVector3(0, 42, 0)
        bodyGroup.addChildNode(body)

        buildLeg(pivot: legPivotL, x: -8.5)
        buildLeg(pivot: legPivotR, x: 8.5)
        buildArm(pivot: armPivotL, x: -23, sign: -1)
        buildArm(pivot: armPivotR, x: 23, sign: 1)

        buildHead()
    }

    private func buildLeg(pivot: SCNNode, x: CGFloat) {
        pivot.position = SCNVector3(x, 17, 0)
        bodyGroup.addChildNode(pivot)

        let leg = capsuleNode(radius: 5.0, height: 10, material: furMaterial)
        leg.position = SCNVector3(0, -4, 0)
        pivot.addChildNode(leg)

        let foot = sphereNode(radius: 5.4, material: furMaterial)
        foot.scale = SCNVector3(1.0, 0.55, 1.25)
        foot.position = SCNVector3(0, -14, 1.2)
        pivot.addChildNode(foot)
    }

    private func buildArm(pivot: SCNNode, x: CGFloat, sign: CGFloat) {
        pivot.position = SCNVector3(x, 42, 0)
        bodyGroup.addChildNode(pivot)

        let arm = capsuleNode(radius: 5.0, height: 9, material: furMaterial)
        arm.position = SCNVector3(sign * 1.5, -5, 0)
        pivot.addChildNode(arm)

        let hand = sphereNode(radius: 5.2, material: furMaterial)
        hand.position = SCNVector3(sign * 2.5, -9.5, 0.5)
        pivot.addChildNode(hand)
    }

    private func buildHead() {
        headPivot.position = SCNVector3(0, 56, 0)
        bodyGroup.addChildNode(headPivot)
        headPivot.addChildNode(headGroup)

        // 兜帽（把上半身罩住）
        let hood = sphereNode(radius: 21, material: furMaterial)
        hood.scale = SCNVector3(1.03, 1.06, 0.98)
        hood.position = SCNVector3(0, 8, 0)
        headGroup.addChildNode(hood)

        // 兜帽顶上的两团绒毛
        for sign in [CGFloat(-1), CGFloat(1)] {
            let peak = sphereNode(radius: 7.5, material: furMaterial)
            peak.scale = SCNVector3(1.0, 1.15, 0.9)
            peak.position = SCNVector3(sign * 11.5, 25, -3)
            headGroup.addChildNode(peak)
        }

        // 光滑的脸（比绒毛亮一点、没有法线噪声）
        let faceNode = sphereNode(radius: 15, material: makeSmoothMaterial(PipPalette.face))
        faceNode.scale = SCNVector3(1.0, 1.12, 0.55)
        faceNode.position = SCNVector3(0, 7, 14)
        headGroup.addChildNode(faceNode)

        // 帽沿：一圈绒毛包住脸的边缘
        let rim = torusNode(ringRadius: 15.4, pipeRadius: 2.9, material: makeFurMaterial(PipPalette.furDeep))
        rim.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)
        rim.position = SCNVector3(0, 7, 16)
        headGroup.addChildNode(rim)

        // 眼睛（小椭圆 + 高光）
        for (group, sign) in [(eyeGroupL, CGFloat(-1)), (eyeGroupR, CGFloat(1))] {
            group.position = SCNVector3(sign * 6.2, 9, 20.8)

            let eye = sphereNode(radius: 2.7, material: makeSmoothMaterial(PipPalette.eye))
            eye.scale = SCNVector3(0.95, 1.25, 0.45)
            group.addChildNode(eye)

            let shine = sphereNode(radius: 0.85, material: makeSmoothMaterial(PipPalette.shine))
            shine.position = SCNVector3(sign * 0.75, 1.0, 1.1)
            group.addChildNode(shine)

            headGroup.addChildNode(group)
        }

        // 腮红
        for sign in [CGFloat(-1), CGFloat(1)] {
            let cheek = sphereNode(radius: 4.4, material: makeSmoothMaterial(PipPalette.cheek.withAlphaComponent(0.62), doubleSided: false))
            cheek.scale = SCNVector3(1.2, 0.78, 0.22)
            cheek.position = SCNVector3(sign * 10.5, 3, 19.6)
            headGroup.addChildNode(cheek)
        }

        // 细弧嘴
        headGroup.addChildNode(mouthNode())
    }

    private func mouthNode() -> SCNNode {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -3.3, y: 0.9))
        path.curve(to: NSPoint(x: 3.3, y: 0.9),
                   controlPoint1: NSPoint(x: -1.5, y: -1.2),
                   controlPoint2: NSPoint(x: 1.5, y: -1.2))
        path.lineWidth = 0.9

        let shape = SCNShape(path: path, extrusionDepth: 0.5)
        shape.chamferRadius = 0.22
        shape.materials = [makeSmoothMaterial(PipPalette.mouth)]

        let node = SCNNode(geometry: shape)
        node.position = SCNVector3(0, 2.6, 21.1)
        return node
    }

    // MARK: 应用姿势

    func apply(_ pose: Pose) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true

        root.position = SCNVector3(pose.feet.x, pose.feet.y, 0)
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

    // MARK: 材质

    private func makeFurMaterial(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = false

        if let normalMap = FurTexture.shared {
            m.normal.contents = normalMap
            m.normal.intensity = 0.85
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(3.5, 3.5, 1)
        }
        return m
    }

    private func makeSmoothMaterial(_ color: NSColor, doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        m.isDoubleSided = doubleSided
        if color.alphaComponent < 1 {
            m.blendMode = .alpha
            m.transparency = color.alphaComponent
            m.diffuse.contents = color.withAlphaComponent(1)
        }
        return m
    }

    // MARK: 几何工具

    private func sphereNode(radius: CGFloat, material: SCNMaterial) -> SCNNode {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 64
        sphere.materials = [material]
        return SCNNode(geometry: sphere)
    }

    private func capsuleNode(radius: CGFloat, height: CGFloat, material: SCNMaterial) -> SCNNode {
        let capsule = SCNCapsule(capRadius: radius, height: height)
        capsule.radialSegmentCount = 40
        capsule.capSegmentCount = 16
        capsule.materials = [material]
        return SCNNode(geometry: capsule)
    }

    private func torusNode(ringRadius: CGFloat, pipeRadius: CGFloat, material: SCNMaterial) -> SCNNode {
        let torus = SCNTorus(ringRadius: ringRadius, pipeRadius: pipeRadius)
        torus.ringSegmentCount = 72
        torus.pipeSegmentCount = 20
        torus.materials = [material]
        return SCNNode(geometry: torus)
    }
}
