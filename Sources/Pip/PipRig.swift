import AppKit
import SceneKit

// MARK: - 配色（米白绒毛 + 奶油脸）

enum PipPalette {
    static let fur       = NSColor.hex(0xE4D7C5)   // 暖米色绒毛
    static let face      = NSColor.hex(0xF3EADD)   // 更亮的奶油脸
    static let cheek     = NSColor.hex(0xE9A296)   // 腮红
    static let eye       = NSColor.hex(0x17191F)   // 近黑，略偏冷
    static let shine     = NSColor.hex(0xEAF2FF)   // 眼里的冷光
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
    private let eyeBaseL = CGPoint(x: -8.7, y: 2.0)
    private let eyeBaseR = CGPoint(x: 8.7, y: 2.0)
    /// 眼神方向（-1…1，已在 Stage 里按朝向翻过），由 setGaze 写入、apply 里统一生效
    private var gaze = CGPoint.zero
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
        let faceNode = sphereNode(radius: 16.5, material: makeSmoothMaterial(PipPalette.face))
        faceNode.scale = SCNVector3(1.03, 1.0, 0.62)
        headGroup.addChildNode(faceNode)

        // 脸和绒毛交界处的一圈软阴影，把生硬的分界线化开
        headGroup.addChildNode(faceShadeNode())

        // 眼睛（小椭圆 + 冷光）
        for (group, sign) in [(eyeGroupL, CGFloat(-1)), (eyeGroupR, CGFloat(1))] {
            group.position = SCNVector3(sign * 8.7, 2.0, 8.4)   // 与 eyeBaseL/R 保持一致

            let eye = sphereNode(radius: 2.9, material: makeSmoothMaterial(PipPalette.eye))
            eye.scale = SCNVector3(0.95, 1.1, 0.5)
            group.addChildNode(eye)

            let shine = sphereNode(radius: 0.62, material: makeSmoothMaterial(PipPalette.shine))
            shine.position = SCNVector3(sign * -0.7, 0.85, 1.0)
            group.addChildNode(shine)

            headGroup.addChildNode(group)
        }

        // 腮红：一张带径向渐变的软片，边缘化开（用球体做会是硬边椭圆）
        for sign in [CGFloat(-1), CGFloat(1)] {
            headGroup.addChildNode(blushNode(sign: sign))
        }

        // 细弧嘴
        headGroup.addChildNode(mouthNode())
    }

    /// 嘴：一串小球沿弧线排开，拼成一条等宽的细微笑（SCNShape 在这种细长弧上没有圆头）
    private func mouthNode() -> SCNNode {
        let node = SCNNode()
        let material = makeSmoothMaterial(PipPalette.mouth)

        let xRadius: CGFloat = 16.5 * 1.03
        let yRadius: CGFloat = 16.5
        let zRadius: CGFloat = 16.5 * 0.62

        let halfWidth: CGFloat = 3.9
        let topY: CGFloat = 0.8
        let dipY: CGFloat = -1.2

        let steps = 11
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // 二次贝塞尔，两端往上翘一点
            let oneMinus = 1 - t
            let x = (2 * oneMinus * t * 0 + oneMinus * oneMinus * -halfWidth + t * t * halfWidth)
            let y = -4.2 + oneMinus * oneMinus * topY + 2 * oneMinus * t * dipY + t * t * topY

            let normalized = 1 - (x * x) / (xRadius * xRadius) - (y * y) / (yRadius * yRadius)
            let z = zRadius * sqrt(max(0.05, normalized)) + 0.55

            let bead = sphereNode(radius: 0.42, material: material)
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
        // 身体整体朝鼠标方向微微倾斜，比只转眼珠明显得多
        bodyGroup.eulerAngles = SCNVector3(0, 0, -pose.bodyLean - gaze.x * 0.05)

        headPivot.eulerAngles = SCNVector3(pose.headPitch - gaze.y * 0.04,
                                           pose.headYaw + gaze.x * 0.12,
                                           pose.headTilt)

        armPivotL.eulerAngles = SCNVector3(0, 0, -pose.armLeft)
        armPivotR.eulerAngles = SCNVector3(0, 0, pose.armRight)

        legPivotL.eulerAngles = SCNVector3(pose.legLeft, 0, 0)
        legPivotR.eulerAngles = SCNVector3(pose.legRight, 0, 0)

        let eyeScale = SCNVector3(1, max(0.08, 1 - pose.blink * 0.95), 1)
        eyeGroupL.scale = eyeScale
        eyeGroupR.scale = eyeScale

        // 眼珠朝鼠标方向滑过去（这个角色没有眼白，靠珠子挪位表达视线）
        let lookX = gaze.x * 2.8
        let lookY = gaze.y * 1.9
        eyeGroupL.position = SCNVector3(eyeBaseL.x + lookX, eyeBaseL.y + lookY, 7.5)
        eyeGroupR.position = SCNVector3(eyeBaseR.x + lookX, eyeBaseR.y + lookY, 7.5)

        SCNTransaction.commit()
    }

    // MARK: 脸的接缝阴影

    private static let faceShadeImage: CGImage? = {
        let size = 256
        guard let context = CGContext(data: nil,
                                      width: size,
                                      height: size,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let shadow = NSColor.hex(0x6B5B49)
        let colors = [shadow.withAlphaComponent(0).cgColor,
                      shadow.withAlphaComponent(0).cgColor,
                      shadow.withAlphaComponent(0.26).cgColor,
                      shadow.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors,
                                        locations: [0, 0.84, 0.93, 1.0]) else { return nil }
        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        context.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: CGFloat(size) / 2,
                                   options: [])
        return context.makeImage()
    }()

    private func faceShadeNode() -> SCNNode {
        let plane = SCNPlane(width: 37, height: 36)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.faceShadeImage
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, 22.0)
        return node
    }

    // MARK: 腮红

    private static let blushImage: CGImage? = {
        let size = 128
        guard let context = CGContext(data: nil,
                                      width: size,
                                      height: size,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let color = PipPalette.cheek
        let colors = [color.withAlphaComponent(0.85).cgColor,
                      color.withAlphaComponent(0.32).cgColor,
                      color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors,
                                        locations: [0, 0.5, 1]) else { return nil }
        let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
        context.drawRadialGradient(gradient,
                                   startCenter: center, startRadius: 0,
                                   endCenter: center, endRadius: CGFloat(size) / 2,
                                   options: [])
        return context.makeImage()
    }()

    /// 一张贴在脸颊上的软渐变片，边缘自然化开
    private func blushNode(sign: CGFloat) -> SCNNode {
        let width: CGFloat = 9.5
        let plane = SCNPlane(width: width, height: width * 0.72)

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.blushImage
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(sign * 9.4, -4.9, 8.6)
        return node
    }

    // MARK: 眼神

    func setGaze(_ direction: CGPoint) {
        gaze = direction
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
