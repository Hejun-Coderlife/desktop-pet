import AppKit
import SceneKit
import Metal
import CoreGraphics

// MARK: - 离屏渲染一张透明背景的 PNG（给用户看造型）

enum Snapshot {

    static func run(outputPath: String) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("✗ 没有可用的 Metal 设备")
            exit(1)
        }

        let canvas = 900
        let built = SceneFactory.makeScene(viewportSize: CGSize(width: canvas, height: canvas))
        built.camera.camera?.orthographicScale = 60
        built.camera.position = SCNVector3(0, 48, 900)
        built.camera.eulerAngles = SCNVector3(0, 0, 0)

        // 站立姿势（微微歪头、手略张开）
        var pose = Pose()
        pose.feet = CGPoint(x: 0, y: 0)
        pose.headTilt = 0.04
        pose.headYaw = 0.0
        pose.armLeft = 0.10
        pose.armRight = -0.10
        built.rig.apply(pose)

        built.shadow.position = SCNVector3(0, 1.5, 1)
        built.shadow.scale = SCNVector3(1, 1, 1)
        built.shadow.opacity = 1

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = built.scene
        renderer.pointOfView = built.camera

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: canvas,
            height: canvas,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        guard let texture = device.makeTexture(descriptor: descriptor),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else {
            print("✗ 创建 Metal 资源失败")
            exit(1)
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        renderer.render(atTime: 0,
                        viewport: CGRect(x: 0, y: 0, width: canvas, height: canvas),
                        commandBuffer: commandBuffer,
                        passDescriptor: pass)

        let bytesPerRow = canvas * 4
        guard let readback = device.makeBuffer(length: bytesPerRow * canvas, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else {
            print("✗ 创建回读缓冲失败")
            exit(1)
        }

        blit.copy(from: texture,
                  sourceSlice: 0,
                  sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: canvas, height: canvas, depth: 1),
                  to: readback,
                  destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * canvas)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytes = readback.contents().bindMemory(to: UInt8.self, capacity: bytesPerRow * canvas)
        let data = Data(bytes: bytes, count: bytesPerRow * canvas)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: canvas,
                                  height: canvas,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo,
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            print("✗ 生成 CGImage 失败")
            exit(1)
        }

        let url = URL(fileURLWithPath: outputPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            print("✗ 无法写入 \(outputPath)")
            exit(1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            print("✗ PNG 编码失败")
            exit(1)
        }

        // —— 自检：四角透明、中间有内容 ——
        func alphaAt(_ x: Int, _ y: Int) -> Int {
            Int(bytes[(y * canvas + x) * 4 + 3])
        }
        let cornerAlphas = [alphaAt(2, 2), alphaAt(canvas - 3, 2), alphaAt(2, canvas - 3), alphaAt(canvas - 3, canvas - 3)]
        let cornersClear = cornerAlphas.allSatisfy { $0 < 8 }

        // 统计不透明像素的包围盒（BGRA，第 0 行是图像顶部）
        var minX = canvas, maxX = 0, minY = canvas, maxY = 0, opaqueCount = 0
        for y in 0..<canvas {
            for x in 0..<canvas where alphaAt(x, y) > 16 {
                opaqueCount += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        print("✓ 已输出 \(outputPath)（\(canvas)x\(canvas)，背景透明）")
        print("  四角 alpha = \(cornerAlphas)（\(cornersClear ? "透明，通过" : "不透明，异常")）")
        if opaqueCount > 0 {
            print("  角色包围盒 \(maxX - minX + 1) x \(maxY - minY + 1) 像素，中心 (\((minX + maxX) / 2), \((minY + maxY) / 2))")
        } else {
            print("  ✗ 画面上没有任何不透明像素，角色没渲染出来")
            exit(1)
        }
    }
}
