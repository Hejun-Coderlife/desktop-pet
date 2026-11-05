import AppKit
import SceneKit

/// 壳层绒毛（shell fur）：在一个部件外面叠 N 层逐渐外扩的同形外壳，
/// 每层按一张随机「毛高」贴图镂空——越外层留下的毛越少，叠起来就是一根根短绒毛，
/// 轮廓边缘会真正毛茸茸，而不是法线贴图那种「表面粗糙但边缘光溜」。
///
/// 实现要点：
/// - 外扩在 geometry shader modifier 里做（沿法线推 furH × furLength，再往下垂一点）
/// - 毛高贴图放在 emission 通道里借道采样，surface modifier 读出来后把 emission 清掉
/// - 镂空用 discard_fragment()，材质保持不透明 → 不需要透明排序，层与层之间不闪
/// - 越靠根部越暗（自阴影），毛尖更浅；再加一圈 fresnel 暖色绒边
enum Fur {

    /// 层数和长度。90 点高的角色，14 层足够；改小能省显卡
    static var layers = 14

    struct Colors {
        var root: NSColor
        var tip: NSColor
        var rim: NSColor
    }

    /// 给 `node` 的几何体加绒毛：自身换成第 0 层（根部、全覆盖），再叠 `layers` 层外壳作为子节点。
    /// - Parameters:
    ///   - length: 毛长（点）
    ///   - tile: 毛高贴图在 UV 上的重复次数，按部件尺寸给，保证毛的粗细在各部件上差不多
    /// - faceHole: 身体上「不长毛」的脸部区域（模型坐标的中心 x、y 和半宽、半高；只在 z>0 的正面生效）
    static func apply(to node: SCNNode, colors: Colors, length: CGFloat, tile: CGSize, layers: Int = Fur.layers,
                      faceHole: SCNVector4? = nil) {
        guard let base = node.geometry else { return }
        node.geometry = base.copy() as? SCNGeometry
        node.geometry?.materials = [material(h: 0, colors: colors, length: length, tile: tile, faceHole: faceHole)]
        for i in 1...max(1, layers) {
            let h = CGFloat(i) / CGFloat(layers)
            guard let g = base.copy() as? SCNGeometry else { continue }
            g.materials = [material(h: h, colors: colors, length: length, tile: tile, faceHole: faceHole)]
            let shell = SCNNode(geometry: g)
            shell.name = "fur.shell.\(i)"
            shell.castsShadow = false
            node.addChildNode(shell)
        }
    }

    // MARK: 材质

    private static let geometryModifier = """
    #pragma arguments
    float furH;
    float furLen;
    #pragma varyings
    float3 furModelPos;
    #pragma body
    out.furModelPos = _geometry.position.xyz;
    float off = furH * furLen;
    _geometry.position.xyz += _geometry.normal * off;
    _geometry.position.y -= furH * furH * furLen * 0.45;
    """

    private static let surfaceModifier = """
    #pragma arguments
    float furH;
    float3 furRoot;
    float3 furTip;
    float3 furRim;
    float4 faceHole;
    #pragma body
    // 脸部禁区：光滑的脸贴在身体曲面上，这一块不长毛（四周的毛自然高出一截，像脸嵌在毛里）
    if (furH > 0.0 && faceHole.z > 0.0 && in.furModelPos.z > 0.0) {
        float2 d = abs((in.furModelPos.xy - faceHole.xy) / faceHole.zw);
        float r = pow(pow(d.x, 2.15) + pow(d.y, 2.15), 1.0 / 2.15);
        if (r < 0.96) { discard_fragment(); }
    }
    float strand = _surface.emission.r;
    if (furH > 0.0 && strand < furH) { discard_fragment(); }
    float3 c = mix(furRoot, furTip, furH * 0.9 + strand * 0.04);
    c *= mix(0.82, 1.0, sqrt(furH));
    _surface.diffuse = float4(c, 1.0);
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float rim = pow(1.0 - saturate(dot(n, v)), 2.2);
    _surface.emission = float4(furRim * rim * (0.05 + 0.10 * furH), 1.0);
    """

    private static func material(h: CGFloat, colors: Colors, length: CGFloat, tile: CGSize, faceHole: SCNVector4?) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.isDoubleSided = false
        m.diffuse.contents = colors.root
        m.emission.contents = strandImage
        m.emission.wrapS = .repeat
        m.emission.wrapT = .repeat
        // 角色实际只有 ~90 点高，一根毛不到一个像素：不开 mipmap 时每帧随机采到不同的毛 → 闪烁噪点。
        // 开了以后远看取平均，绒毛融成一片柔和的绒面，只在轮廓上留下毛边。
        m.emission.mipFilter = .linear
        m.emission.minificationFilter = .linear
        m.emission.magnificationFilter = .linear
        m.emission.contentsTransform = SCNMatrix4MakeScale(tile.width, tile.height, 1)
        m.shaderModifiers = [.geometry: geometryModifier, .surface: surfaceModifier]
        m.setValue(NSNumber(value: Float(h)), forKey: "furH")
        m.setValue(NSNumber(value: Float(length)), forKey: "furLen")
        m.setValue(vec(colors.root), forKey: "furRoot")
        m.setValue(vec(colors.tip), forKey: "furTip")
        m.setValue(vec(colors.rim), forKey: "furRim")
        m.setValue(NSValue(scnVector4: faceHole ?? SCNVector4(0, 0, 0, 0)), forKey: "faceHole")
        return m
    }

    private static func vec(_ c: NSColor) -> NSValue {
        let s = c.usingColorSpace(.sRGB) ?? c
        return NSValue(scnVector3: SCNVector3(s.redComponent, s.greenComponent, s.blueComponent))
    }

    // MARK: 毛高贴图

    /// 每个像素一根毛，值 = 这根毛有多长（0…1）。分布偏长一点，外层也留得住毛尖。
    /// 可平铺（纯逐像素随机，没有低频成分，平铺无接缝）。
    static let strandImage: CGImage? = {
        let size = 128
        var px = [UInt8](repeating: 0, count: size * size)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for i in 0..<(size * size) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
            px[i] = UInt8(min(255, pow(r, 0.75) * 255))
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }()
}
