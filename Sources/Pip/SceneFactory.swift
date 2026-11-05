import AppKit
import SceneKit

/// 场景搭建：正交相机（1 世界单位 = 1 屏幕点）、灯光、角色、地面阴影
enum SceneFactory {

    struct Built {
        let scene: SCNScene
        let camera: SCNNode
        let rig: PipRig
        let shadow: SCNNode
    }

    static func makeScene(viewportSize: CGSize) -> Built {
        let scene = SCNScene()
        scene.background.contents = nil

        // 相机：正交投影，看 -Z，世界坐标和屏幕点 1:1
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(max(1, viewportSize.height / 2))
        camera.zNear = 1
        camera.zFar = 4000
        camera.wantsHDR = false

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(viewportSize.width / 2, viewportSize.height / 2, 1200)
        scene.rootNode.addChildNode(cameraNode)

        // 环境光（拉高，做出柔和的漫反射）
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = NSColor(white: 0.92, alpha: 1)
        ambient.intensity = 780
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // 主光：左上往前打
        let key = SCNLight()
        key.type = .directional
        key.color = NSColor(white: 1.0, alpha: 1)
        key.intensity = 520
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.55, -0.5, 0)
        scene.rootNode.addChildNode(keyNode)

        // 补光：右后方一点暖色
        let fill = SCNLight()
        fill.type = .directional
        fill.color = NSColor(srgbRed: 1.0, green: 0.96, blue: 0.92, alpha: 1)
        fill.intensity = 260
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(0.35, 0.9, 0)
        scene.rootNode.addChildNode(fillNode)

        let rig = PipRig()
        scene.rootNode.addChildNode(rig.root)

        let shadow = makeShadowNode()
        scene.rootNode.addChildNode(shadow)

        return Built(scene: scene, camera: cameraNode, rig: rig, shadow: shadow)
    }

    // MARK: 脚底接触阴影（竖直面片 + 径向渐变，正交正面看就是椭圆）

    static func makeShadowNode() -> SCNNode {
        let plane = SCNPlane(width: 64, height: 22)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = shadowImage()
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.name = "pip.shadow"
        node.position = SCNVector3(0, 1.5, 1)
        node.castsShadow = false
        node.renderingOrder = -1
        return node
    }

    private static func shadowImage() -> CGImage? {
        let width = 128
        let height = 48
        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let colors = [
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.55),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.28),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)
        ] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors,
                                        locations: [0, 0.55, 1]) else {
            return nil
        }
        let center = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: CGFloat(height) / 2,
                               options: [.drawsAfterEndLocation])
        return ctx.makeImage()
    }
}
