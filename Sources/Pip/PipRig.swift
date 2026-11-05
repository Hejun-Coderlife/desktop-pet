import AppKit
import SceneKit

// MARK: - 配色（米白绒毛 + 奶油脸）

enum PipPalette {
    static let fur       = NSColor.hex(0xE4D7C5)   // 暖米色绒毛（整体基调）
    static let furRoot   = NSColor.hex(0xCDB89F)   // 毛根：更深，做出绒毛的厚度
    static let furTip    = NSColor.hex(0xF4ECE0)   // 毛尖：更浅
    static let furRim    = NSColor.hex(0xFFE9CC)   // 逆光绒边：暖
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

    /// 脸的椭圆（宽 38、高 33），不是正圆
    /// 脸：偏大的圆角方形（超椭圆），占头部大半——参考原版，下巴干净、不被毛盖住
    private let faceWidth: CGFloat = 43
    private let faceHeight: CGFloat = 40
    /// 脸那张软片的深度：比肚子最鼓的地方再靠前一点，否则下半张脸会被绒毛吃掉
    /// 长毛（6.2 点）会从身体表面往前伸，脸片要比毛尖更靠前，否则下巴被毛吃掉
    private let facePanelZ: CGFloat = 19.5
    /// 五官（眼、腮红、嘴）比脸的软片再靠前一点
    private let featureZ: CGFloat = 20.5

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
    private var blushNodes: [SCNNode] = []
    /// 不跟着朝向镜像的挂件（字要正着读）：z 和牌子
    private let unmirrored = SCNNode()
    private var zzzNodes: [SCNNode] = []
    private let signNode = SCNNode()
    private var signShown: String?

    /// 身体轮廓（从下到上）：最宽 60 点，头顶是圆顶
    static let bodyProfile: [(y: CGFloat, r: CGFloat)] = [
        (5.0, 0), (5.5, 7.0), (7.0, 14.0), (10.0, 20.5), (14.0, 25.0),
        (19.0, 28.0), (25.0, 29.5), (32.0, 30.0), (39.0, 30.0), (46.0, 29.5),
        (52.0, 28.5), (58.0, 27.0), (64.0, 24.3), (68.0, 24.0), (72.0, 23.2),
        (76.0, 21.5), (80.0, 18.8), (83.0, 15.4), (85.0, 11.6), (86.5, 6.8),
        (87.0, 0)
    ]

    private lazy var furMaterial: SCNMaterial = makeFurMaterial(PipPalette.fur)
    private let furColors = Fur.Colors(root: PipPalette.furRoot, tip: PipPalette.furTip, rim: PipPalette.furRim)
    private var legBaseY: CGFloat = 12

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
        let body = Lathe.node(profile: Self.bodyProfile, segments: 96, material: furMaterial)
        // 毛的粗细要接近 1 个屏幕点：周长约 188 点 / (2.8 × 128) ≈ 0.5 点一根（0.9 太粗像刺猬，0.08 太细会闪）。
        // 再细就会小于一个像素，每帧采到不同的毛 → 闪烁噪点（实测过）
        Fur.apply(to: body, colors: furColors, length: 5.4, tile: CGSize(width: 4.6, height: 2.0), layers: 20)
        bodyGroup.addChildNode(body)

        buildLeg(pivot: legPivotL, x: -9)
        buildLeg(pivot: legPivotR, x: 9)
        buildArm(pivot: armPivotL, x: -26, sign: -1)
        buildArm(pivot: armPivotR, x: 26, sign: 1)

        buildHead()
        buildExtras()
        Outfit.current().attach(to: headGroup, body: bodyGroup)
    }

    // MARK: z 和牌子

    private func buildExtras() {
        bodyGroup.addChildNode(unmirrored)
        for i in 0..<3 {
            let size: CGFloat = 9 + CGFloat(i) * 3
            let plane = SCNPlane(width: size, height: size)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = Self.textImage("z", fontSize: 64, color: NSColor.hex(0x6E7FA8), size: CGSize(width: 64, height: 64))
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.isHidden = true
            unmirrored.addChildNode(n)
            zzzNodes.append(n)
        }
        signNode.isHidden = true
        unmirrored.addChildNode(signNode)
    }

    /// 把一段文字画成透明底的贴图
    static func textImage(_ text: String, fontSize: CGFloat, color: NSColor, size: CGSize, background: NSColor? = nil) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        if let background {
            let path = NSBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), xRadius: 18, yRadius: 18)
            background.setFill()
            path.fill()
            NSColor.hex(0xB89C7E).setStroke()
            path.lineWidth = 4
            path.stroke()
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let str = NSAttributedString(string: text, attributes: attrs)
        let h = str.boundingRect(with: size, options: [.usesLineFragmentOrigin]).height
        str.draw(in: CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h))
        image.unlockFocus()
        return image
    }

    private func updateSign(_ text: String?) {
        guard text != signShown else { return }
        signShown = text
        signNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let text else { signNode.isHidden = true; return }
        let plane = SCNPlane(width: 64, height: 30)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.textImage(text, fontSize: 46, color: NSColor.hex(0x5A4636),
                                            size: CGSize(width: 384, height: 180), background: NSColor.hex(0xFFF7EA))
        m.isDoubleSided = true
        plane.materials = [m]
        let board = SCNNode(geometry: plane)
        // 两根小木棍连到爪子
        let stickMaterial = makeSmoothMaterial(NSColor.hex(0xB89C7E))
        for x in [CGFloat(-16), 16] {
            let stick = SCNNode(geometry: SCNCylinder(radius: 0.9, height: 14))
            stick.geometry?.materials = [stickMaterial]
            stick.position = SCNVector3(x, -20, -0.5)
            board.addChildNode(stick)
        }
        signNode.addChildNode(board)
        signNode.position = SCNVector3(0, 116, 26)
        signNode.isHidden = false
    }

    private func buildLeg(pivot: SCNNode, x: CGFloat) {
        pivot.position = SCNVector3(x, 12, 0)
        bodyGroup.addChildNode(pivot)

        // 腿几乎全藏在绒毛里，只露出小脚
        let leg = capsuleNode(radius: 5.0, height: 10, material: furMaterial)
        leg.position = SCNVector3(0, -4, 0)
        pivot.addChildNode(leg)

        // 圆鼓鼓的小脚（不是扁圆饼），带绒毛
        let foot = sphereNode(radius: 5.6, material: furMaterial)
        foot.scale = SCNVector3(1.05, 0.68, 1.25)
        foot.position = SCNVector3(0, -8.4, 1.6)
        Fur.apply(to: foot, colors: furColors, length: 1.6, tile: CGSize(width: 0.6, height: 0.3))
        pivot.addChildNode(foot)
    }

    private func buildArm(pivot: SCNNode, x: CGFloat, sign: CGFloat) {
        pivot.position = SCNVector3(x * 1.04, 44, 2)
        bodyGroup.addChildNode(pivot)

        // 短粗的圆头小爪：胶囊形，上半截埋进身体、往外下方斜着长出来，带绒毛
        let arm = capsuleNode(radius: 6.2, height: 17, material: furMaterial)
        arm.position = SCNVector3(sign * 4.0, -6.0, 0)
        arm.eulerAngles = SCNVector3(0, 0, sign * 0.45)
        Fur.apply(to: arm, colors: furColors, length: 3.0, tile: CGSize(width: 0.8, height: 0.5), layers: 16)
        pivot.addChildNode(arm)
    }

    private func buildHead() {
        // 脸这一坨绕自己的中心转，不会在绒毛上滑来滑去
        headPivot.position = SCNVector3(0, 60, 18)
        bodyGroup.addChildNode(headPivot)
        headPivot.addChildNode(headGroup)

        // 光滑的脸：一张画好羽化边缘的椭圆软片。
        // 用球体不行——肚子在脸下方往外鼓，球的下缘会被绒毛切掉，而且球面边缘的羽化几乎没有宽度。
        headGroup.addChildNode(facePanelNode())

        // 眼睛（小椭圆 + 冷光）
        for (group, sign) in [(eyeGroupL, CGFloat(-1)), (eyeGroupR, CGFloat(1))] {
            group.position = SCNVector3(sign * 8.7, 2.0, featureZ)

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
            let b = blushNode(sign: sign)
            blushNodes.append(b)
            headGroup.addChildNode(b)
        }

        // 细弧嘴
        headGroup.addChildNode(mouthNode())
    }

    /// 嘴：一串小球沿弧线排开，拼成一条等宽的细微笑（SCNShape 在这种细长弧上没有圆头）
    private func mouthNode() -> SCNNode {
        let node = SCNNode()
        let material = makeSmoothMaterial(PipPalette.mouth)

        let halfWidth: CGFloat = 3.9
        let topY: CGFloat = 0.8
        let dipY: CGFloat = -1.2

        // 二次贝塞尔，两端往上翘一点；扫成一根连续的「绣线」圆管
        let steps = 24
        var points: [SCNVector3] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let oneMinus = 1 - t
            let x = oneMinus * oneMinus * -halfWidth + t * t * halfWidth
            let y = -4.2 + oneMinus * oneMinus * topY + 2 * oneMinus * t * dipY + t * t * topY
            points.append(SCNVector3(x, y, featureZ + 0.2))
        }
        node.addChildNode(Tube.node(points: points, radius: 0.42, material: material))
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
        bodyGroup.eulerAngles = SCNVector3(0, pose.bodyYaw, -pose.bodyLean - gaze.x * 0.05)

        headPivot.eulerAngles = SCNVector3(pose.headPitch - gaze.y * 0.04,
                                           pose.headYaw + gaze.x * 0.12,
                                           pose.headTilt)

        armPivotL.eulerAngles = SCNVector3(0, 0, -pose.armLeft)
        armPivotR.eulerAngles = SCNVector3(0, 0, pose.armRight)

        legPivotL.eulerAngles = SCNVector3(pose.legLeft, 0, -pose.legSideLeft)
        legPivotR.eulerAngles = SCNVector3(pose.legRight, 0, pose.legSideRight)
        legPivotL.position.y = legBaseY + pose.liftLeft
        legPivotR.position.y = legBaseY + pose.liftRight

        // 笑眼：压成一条细缝、略往上提（远看就是弯弯的 ^ ^）
        let open = max(0.08, 1 - pose.blink * 0.95) * (1 - pose.happyEyes * 0.78)
        let es = pose.eyeScale
        let eyeScale = SCNVector3(es * (1 + pose.happyEyes * 0.25), es * open, es)
        eyeGroupL.scale = eyeScale
        eyeGroupR.scale = eyeScale
        for n in blushNodes { n.opacity = min(1, 0.55 * pose.blush) }

        // 不镜像的挂件：父节点被 facing 翻了，这里再翻回来
        unmirrored.scale = SCNVector3(pose.facing, 1, 1)
        for (i, n) in zzzNodes.enumerated() {
            guard pose.zzz >= 0 else { n.isHidden = true; continue }
            let phase = (pose.zzz * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
            n.isHidden = false
            n.position = SCNVector3(20 + phase * 14, 82 + phase * 34, 24)
            n.opacity = sin(phase * .pi)
        }
        updateSign(pose.sign)

        // 眼珠朝鼠标方向滑过去（这个角色没有眼白，靠珠子挪位表达视线）。
        // 两只眼的 z 相同，滑多远都不会被脸切掉，大小一只是对得上的。
        let lookX = gaze.x * 2.8
        let lookY = gaze.y * 1.9
        eyeGroupL.position = SCNVector3(eyeBaseL.x + lookX, eyeBaseL.y + lookY, featureZ)
        eyeGroupR.position = SCNVector3(eyeBaseR.x + lookX, eyeBaseR.y + lookY, featureZ)

        SCNTransaction.commit()
    }

    // MARK: 脸（椭圆软片）

    /// 512×512 的椭圆纹理：奶油色竖渐变 + 边缘往暖褐色收（不是压灰），最外圈 alpha 化开
    private static let faceImage: CGImage? = {
        let size = 512
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        let top = (r: 0.996, g: 0.980, b: 0.957)      // 上：近白奶油
        let bottom = (r: 0.960, g: 0.925, b: 0.874)   // 下：略暖沉
        let rimTone = (r: 0.930, g: 0.880, b: 0.810)  // 边缘：往绒毛色收（不再是发脏的灰褐）
        let featherStart: Double = 0.80               // 最外一圈是「被绒毛盖住」的毛边
        let featherEnd: Double = 1.0
        // 每个角度一根毛：决定这根毛盖进脸里多深 → 边缘是参差的绒毛，而不是一圈模糊渐变
        var strands = [Double](repeating: 0, count: 720)
        var seed: UInt64 = 0x2545F4914F6CDD1D
        for i in 0..<strands.count {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            strands[i] = Double((seed >> 33) & 0xFFFF) / Double(0xFFFF)
        }

        for y in 0..<size {
            for x in 0..<size {
                let nx = (Double(x) + 0.5) / Double(size) * 2 - 1
                let ny = (Double(y) + 0.5) / Double(size) * 2 - 1
                // 超椭圆（指数 2.5）：圆角方形的脸，比正椭圆饱满
                let pw = 2.5
                let rho = pow(pow(abs(nx), pw) + pow(abs(ny), pw), 1 / pw)

                var alpha = 1.0
                var furCover = 0.0
                if rho > featherStart {
                    let t = min(1, (rho - featherStart) / (featherEnd - featherStart))
                    let angle = atan2(ny, nx) + .pi
                    let k = Int(angle / (2 * .pi) * Double(strands.count)) % strands.count
                    let reach = 0.25 + 0.75 * strands[k]          // 这根毛盖进来多深
                    // 毛只从头顶和两侧盖进来；下半圈（ny > 0.25，图片里 y 向下）是干净的下巴
                    let hoodMask = max(0, min(1, (0.25 - ny) / 0.35))
                    if t > 1 - reach { furCover = min(1, (t - (1 - reach)) / max(reach, 0.01) * 1.6) * hoodMask }
                    alpha = 1 - pow(t, 6)                          // 只在最外缘才真正透明
                }

                let t = (ny + 1) / 2
                var r = top.r + (bottom.r - top.r) * t
                var g = top.g + (bottom.g - top.g) * t
                var b = top.b + (bottom.b - top.b) * t

                // 越靠边缘越往暖褐收，读起来是脸的弧度转进去，而不是一张发光的白纸
                let v = min(1, max(0, (rho - 0.55) / 0.45))
                let shade = v * v * (3 - 2 * v) * 0.25
                r += (rimTone.r - r) * shade
                g += (rimTone.g - g) * shade
                b += (rimTone.b - b) * shade
                // 盖进来的绒毛：用毛尖色
                let tip = (r: 0.957, g: 0.925, b: 0.878)
                r += (tip.r - r) * furCover
                g += (tip.g - g) * furCover
                b += (tip.b - b) * furCover

                let index = (y * size + x) * 4
                pixels[index]     = UInt8(max(0, min(255, r * alpha * 255)))
                pixels[index + 1] = UInt8(max(0, min(255, g * alpha * 255)))
                pixels[index + 2] = UInt8(max(0, min(255, b * alpha * 255)))
                pixels[index + 3] = UInt8(max(0, min(255, alpha * 255)))
            }
        }

        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: size,
                       height: size,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }()

    private func facePanelNode() -> SCNNode {
        let plane = SCNPlane(width: faceWidth, height: faceHeight)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = Self.faceImage
        material.blendMode = .alpha
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.position = SCNVector3(0, 0, facePanelZ)
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
        node.position = SCNVector3(sign * 9.8, -5.0, featureZ + 0.1)
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
