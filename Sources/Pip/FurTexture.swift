import Foundation
import CoreGraphics

/// 程序生成可平铺的「绒毛」法线贴图（值噪声 → 高度场 → 法线）
/// 90 像素高的角色用不上真正的毛发几何，法线贴图 + 柔和光照就够读出绒感了。
enum FurTexture {

    private static var cached: CGImage?

    static var shared: CGImage? {
        if let cached { return cached }
        cached = makeNormalMap(size: 512, frequency: 22, strength: 2.0)
        return cached
    }

    static func makeNormalMap(size: Int, frequency: Float, strength: Float) -> CGImage? {
        var heights = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let fy = Float(y) / Float(size) * frequency
            for x in 0..<size {
                let fx = Float(x) / Float(size) * frequency
                let base = noise(fx, fy)
                let mid = noise(fx * 2.3 + 17.3, fy * 2.3 + 5.1)
                let fine = noise(fx * 4.9 + 3.7, fy * 4.9 + 11.9)
                heights[y * size + x] = base * 0.55 + mid * 0.30 + fine * 0.15
            }
        }

        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let left = heights[y * size + (x - 1 + size) % size]
                let right = heights[y * size + (x + 1) % size]
                let up = heights[((y - 1 + size) % size) * size + x]
                let down = heights[((y + 1) % size) * size + x]

                var nx = (left - right) * strength
                var ny = (down - up) * strength
                var nz: Float = 1
                let length = sqrt(nx * nx + ny * ny + nz * nz)
                nx /= length
                ny /= length
                nz /= length

                let index = (y * size + x) * 4
                pixels[index] = UInt8(clamp((nx * 0.5 + 0.5) * 255))
                pixels[index + 1] = UInt8(clamp((ny * 0.5 + 0.5) * 255))
                pixels[index + 2] = UInt8(clamp((nz * 0.5 + 0.5) * 255))
                pixels[index + 3] = 255
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
    }

    // MARK: 值噪声

    private static func hash(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= (h >> 16)
        return Float(h % 65_536) / 65_535.0
    }

    private static func noise(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floor(x))
        let yi = Int(floor(y))
        let xf = x - floor(x)
        let yf = y - floor(y)

        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)

        let a = hash(xi, yi)
        let b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1)
        let d = hash(xi + 1, yi + 1)

        return a * (1 - u) * (1 - v)
            + b * u * (1 - v)
            + c * (1 - u) * v
            + d * u * v
    }

    private static func clamp(_ v: Float) -> Float {
        min(max(v, 0), 255)
    }
}
