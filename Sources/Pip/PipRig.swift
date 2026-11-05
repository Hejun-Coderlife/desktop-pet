import AppKit
import SceneKit

// MARK: - 配色（米白绒毛 + 奶油脸）

enum PipPalette {
    static let fur       = NSColor.hex(0xF7EFE2)   // 米白绒毛
    static let face      = NSColor.hex(0xF2E6D3)   // 奶油色光滑脸
    static let cheek     = NSColor.hex(0xE9A99C)   // 腮红
    static let eye       = NSColor.hex(0x161513)   // 近黑
    static let shine     = NSColor.hex(0xE8F0FF)   // 眼里的冷光
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
///        ├ 身体（钟形绒毛）
///        ├ armPivotL / armPivotR（肩关节）→ 绒毛手臂
///        ├ legPivotL / legPivotR（髋关节）→ 短腿 + 小脚
///        └ headPivot（颈关节）→ headGroup → 兜帽 + 光滑脸 + 眼睛 + 腮红 + 细弧嘴
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
    /// 眼珠的原始位置，眼神偏移以它为基准
    private let eyeBaseL = CGPoint(x: -7.6, y: 2.2)
    private let eyeBaseR = CGPoint(x: 7.6, y: 2.2)
    private let armPivotL = SCNNode()
    private let armPivotR = SCNNode()
    private let legPivotL = SCNNode()
    private let legPivotR = SCNNode()

    /// 身体轮廓（从下到上）：最宽 60 点，头顶是圆顶
    static let bodyProfile: [(y: CGFloat, r: CGFloat)] = [
        (5.0, 0), (5.5, 7.0), (7.0, 14.0), (10.0, 20.5), (14.0, 25.0),
        (19.0, 28.0), (25.0, 29.5), (32.0, 30.0), (39.0, 30.0), (46.0, 29.5),
        (52.0, 28.5), (58.0, 27.0), (64.0, 24.3), (68.0, 24.0), (72.0, 23.2),
        (76.0, 21.5), (80.0, 18.8), (83.0, 15.4), (85.0, 11.6), (86.5, 6.8),
        (87.0, 0)
    ]

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

        // 身体：一条轮廓线转一圈出来的钟形绒毛（兜帽和身体连成一片，没有接缝）
        bodyGroup.addChildNode(Lathe.node(profile: Self.bodyProfile,
                                          segments: 96,
                                          material: furMaterial))

        buildLeg(pivot: legPivotL, x: -9)
        buildLeg(pivot: legPivotR, x: 9)
        buildArm(pivot: armPivotL, x: -26, sign: -1)
        buildArm(pivot: armPivotR, x: 26, sign: 1)

        buildHead()
    }

    private func buildLeg(pivot: SCNNode, x: CGFloat) {
        pivot.position = SCNVector3(x, 12, 0)
        bodyGroup.addChildNode(pivot)

        // 腿几乎全藏在绒毛里，只露出小脚
        let leg = capsuleNode(radius: 5.0, height: 10, material: furMaterial)
        leg.position = SCNVector3(0, -4, 0)
        pivot.addChildNode(leg)

        let foot = sphereNode(radius: 5.4, material: furMaterial)
        foot.scale = SCNVector3(1.0, 0.5, 1.2)
        foot.position = SCNVector3(0, -9, 1.2)
        pivot.addChildNode(foot)
    }

    private func buildArm(pivot: SCNNode, x: CGFloat, sign: CGFloat) {
        pivot.position = SCNVector3(x, 44, 0)
        bodyGroup.addChildNode(pivot)

        // 连指手套式的一坨绒毛手臂，一半埋进身体
        let arm = sphereNode(radius: 7.5, material: furMaterial)
        arm.scale = SCNVector3(1.0, 1.05, 0.9)
        arm.position = SCNVector3(sign * 3.0, -5, 0)
        pivot.addChildNode(arm)
    }

    private func buildHead() {
        // 脸这一坨绕自己的中心转，不会在绒毛上滑来滑去
        headPivot.position = SCNVector3(0, 62, 18)
        bodyGroup.addChildNode(headPivot)
        headPivot.addChildNode(headGroup)

        // 光滑的脸：微微鼓出来，边缘直接陷进绒毛里
        let faceNode = sphereNode(radius: 15.5, material: makeSmoothMaterial(PipPalette.face))
        faceNode.scale = SCNVector3(1.0, 1.1, 0.58)
        headGroup.addChildNode(faceNode)

        // 眼睛（小椭圆 + 冷光）
        for (group, sign) in [(eyeGroupL, CGFloat(-1)), (eyeGroupR, CGFloat(1))] {
            group.position = SCNVector3(sign * 7.6, 2.2, 7.5)   // 与 eyeBaseL/R 保持一致

            let eye = sphereNode(radius: 3.2, material: makeSmoothMaterial(PipPalette.eye))
            eye.scale = SCNVector3(0.95, 1.15, 0.45)
            group.addChildNode(eye)

            let shine = sphereNode(radius: 0.8, material: makeSmoothMaterial(PipPalette.shine))
            shine.position = SCNVector3(sign * -0.8, 1.0, 1.2)
            group.addChildNode(shine)

            headGroup.addChildNode(group)
        }

        // 腮红
        for sign in [CGFloat(-1), CGFloat(1)] {
            let cheek = sphereNode(radius: 3.6, material: makeSmoothMaterial(PipPalette.cheek.withAlphaComponent(0.45)))
            cheek.scale = SCNVector3(1.25, 0.8, 0.2)
            cheek.position = SCNVector3(sign * 10.4, -5.0, 7.4)
            headGroup.addChildNode(cheek)
        }

        // 细弧嘴
        headGroup.addChildNode(mouthNode())
    }

    /// 嘴：一串小球沿弧线排开，拼成一条等宽的细微笑（SCNShape 在这种细长弧上没有圆头）
    private func mouthNode() -> SCNNode {
        let node = SCNNode()
        let material = makeSmoothMaterial(PipPalette.mouth)

        let xRadius: CGFloat = 15.5
        let yRadius: CGFloat = 17.05          // 15.5 * 1.1
        let zRadius: CGFloat = 8.99           // 15.5 * 0.58

        let halfWidth: CGFloat = 4.6
        let topY: CGFloat = 1.0
        let dipY: CGFloat = -1.6

        let steps = 13
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // 二次贝塞尔，两端往上翘一点
            let oneMinus = 1 - t
            let x = (2 * oneMinus * t * 0 + oneMinus * oneMinus * -halfWidth + t * t * halfWidth)
            let y = oneMinus * oneMinus * topY + 2 * oneMinus * t * dipY + t * t * topY

            let normalized = 1 - (x * x) / (xRadius * xRadius) - (y * y) / (yRadius * yRadius)
            let z = zRadius * sqrt(max(0.05, normalized)) + 0.45

            let bead = sphereNode(radius: 0.52, material: material)
            bead.position = SCNVector3(x, y, z)
            node.addChildNode(bead)
        }
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

    // MARK: 眼神

    func setGaze(_ direction: CGPoint) {
        let dx = direction.x * 2.2
        let dy = direction.y * 1.6

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        eyeGroupL.position = SCNVector3(eyeBaseL.x + dx, eyeBaseL.y + dy, 7.5)
        eyeGroupR.position = SCNVector3(eyeBaseR.x + dx, eyeBaseR.y + dy, 7.5)
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
            m.normal.intensity = 0.7
            m.normal.wrapS = .repeat
            m.normal.wrapT = .repeat
            m.normal.contentsTransform = SCNMatrix4MakeScale(3.5, 3.5, 1)
        }
        return m
    }

    private func makeSmoothMaterial(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.isDoubleSided = false
        if color.alphaComponent < 1 {
            m.diffuse.contents = color.withAlphaComponent(1)
            m.blendMode = .alpha
            m.transparency = color.alphaComponent
        } else {
            m.diffuse.contents = color
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
}
