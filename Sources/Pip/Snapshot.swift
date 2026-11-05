import AppKit
import SceneKit
import Metal
import CoreGraphics

// MARK: - 离屏渲染（给用户看造型 / 给自己验证动画姿势）

enum Snapshot {

    // MARK: 单张站立图

    static func run(outputPath: String) {
        let canvas = 900
        let built = SceneFactory.makeScene(viewportSize: CGSize(width: canvas, height: canvas))
        built.camera.camera?.orthographicScale = 60
        built.camera.position = SCNVector3(0, 48, 900)
        built.camera.eulerAngles = SCNVector3(0, 0, 0)

        // 站立姿势（微微歪头、手略张开）
        var pose = Pose()
        pose.feet = CGPoint(x: 0, y: 0)
        pose.headTilt = 0.04
        pose.armLeft = 0.10
        pose.armRight = -0.10
        built.rig.apply(pose)

        built.shadow.position = SCNVector3(0, 1.5, 1)
        built.shadow.scale = SCNVector3(1, 1, 1)
        built.shadow.opacity = 1

        guard let image = render(scene: built.scene,
                                 camera: built.camera,
                                 width: canvas,
                                 height: canvas) else {
            print("✗ 渲染失败")
            exit(1)
        }

        guard write(image: image, to: outputPath) else {
            print("✗ 无法写入 \(outputPath)")
            exit(1)
        }

        print("✓ 已输出 \(outputPath)（\(canvas)x\(canvas)，背景透明）")
        report(image: image)
    }

    // MARK: 五种姿势的对照图（自己检查动画用）

    static func runSheet(outputPath: String) {
        let width = 2000
        let height = 560
        let built = SceneFactory.makeScene(viewportSize: CGSize(width: width, height: height))
        built.camera.camera?.orthographicScale = 130
        built.camera.position = SCNVector3(0, 118, 900)
        built.camera.eulerAngles = SCNVector3(0, 0, 0)

        let worldSize = CGSize(width: 4000, height: 900)
        let xs: [CGFloat] = [-340, -170, 0, 170, 340]

        let idle = PetWorld(size: worldSize, groundY: 0, seed: 1)
        idle.preview(state: .idle, time: 1.2, feet: CGPoint(x: xs[0], y: 0))

        let walk = PetWorld(size: worldSize, groundY: 0, seed: 2)
        walk.preview(state: .walk, time: 2.0, feet: CGPoint(x: xs[1], y: 0), walkPhase: 1.0)

        let grabbed = PetWorld(size: worldSize, groundY: 0, seed: 3)
        grabbed.preview(state: .grabbed, time: 2.0, feet: CGPoint(x: xs[2], y: 0),
                        grabVelocity: CGVector(dx: 320, dy: 0))

        let falling = PetWorld(size: worldSize, groundY: 0, seed: 4)
        falling.preview(state: .falling, time: 3.0, feet: CGPoint(x: xs[3], y: 0),
                        velocity: CGVector(dx: 150, dy: -900))

        let landing = PetWorld(size: worldSize, groundY: 0, seed: 5)
        landing.preview(state: .landing, time: 4.0, feet: CGPoint(x: xs[4], y: 0),
                        stateTime: PetWorld.landingDuration * 0.28)

        let worlds = [idle, walk, grabbed, falling, landing]
        let rigs = [built.rig] + (1..<worlds.count).map { _ in PipRig() }

        for (index, pair) in zip(worlds, rigs).enumerated() {
            let (world, rig) = pair
            rig.apply(PetAnimator.pose(for: world))
            if index > 0 {
                built.scene.rootNode.addChildNode(rig.node)
            }
            let shadow = SceneFactory.makeShadowNode()
            shadow.position = SCNVector3(xs[index], 1.5, 1)
            built.scene.rootNode.addChildNode(shadow)
        }
        built.shadow.isHidden = true   // 用自己加的那批阴影

        guard let image = render(scene: built.scene,
                                 camera: built.camera,
                                 width: width,
                                 height: height) else {
            print("✗ 渲染失败")
            exit(1)
        }
        guard write(image: image, to: outputPath) else {
            print("✗ 无法写入 \(outputPath)")
            exit(1)
        }
        print("✓ 已输出姿势对照图 \(outputPath)（顺序：发呆 / 走路 / 被拎起 / 下落 / 落地）")
        report(image: image)
    }

    // MARK: 渲染到纹理再读回

    private static func render(scene: SCNScene, camera: SCNNode, width: Int, height: Int) -> CGImage? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            return nil
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        renderer.render(atTime: 0,
                        viewport: CGRect(x: 0, y: 0, width: width, height: height),
                        commandBuffer: commandBuffer,
                        passDescriptor: pass)

        let bytesPerRow = width * 4
        guard let readback = device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            return nil
        }

        blit.copy(from: texture,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback,
                  destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytes = readback.contents().bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        let data = Data(bytes: bytes, count: bytesPerRow * height)

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width,
                       height: height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo,
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    private static func write(image: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: 自检：四角是否透明、角色画出来多大

    private static func report(image: CGImage) {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow

        func alphaAt(_ x: Int, _ y: Int) -> Int {
            Int(bytes[y * bytesPerRow + x * 4 + 3])
        }

        let corners = [alphaAt(2, 2), alphaAt(width - 3, 2), alphaAt(2, height - 3), alphaAt(width - 3, height - 3)]
        let cornersClear = corners.allSatisfy { $0 < 8 }

        var minX = width, maxX = 0, minY = height, maxY = 0, count = 0
        for y in 0..<height {
            for x in 0..<width where alphaAt(x, y) > 16 {
                count += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        print("  四角 alpha = \(corners)（\(cornersClear ? "透明，通过" : "不透明，异常")）")
        if count > 0 {
            print("  角色包围盒 \(maxX - minX + 1) x \(maxY - minY + 1) 像素，中心 (\((minX + maxX) / 2), \((minY + maxY) / 2))")
        } else {
            print("  ✗ 画面上没有任何不透明像素")
        }
    }
}
