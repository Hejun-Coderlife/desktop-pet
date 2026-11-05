import Foundation
import CoreGraphics

/// 程序生成可平铺的「绒毛」法线贴图（值噪声 → 高度场 → 法线）
/// 90 像素高的角色用不上真正的毛发几何，法线贴图 + 柔和光照就够读出绒感了。
/// 噪声必须是周期的，否则贴图平铺时会出现一条条可见的接缝。
enum FurTexture {

    private static var cached: CGImage?

    static var shared: CGImage? {
        if let cached { return cached }
        cached = makeNormalMap(size: 512, strength: 2.0)
        return cached
    }

    static func makeNormalMap(size: Int, strength: Float) -> CGImage? {
        // 三倍频：16 / 32 / 64 个格，都是 2 的幂，直接按位与就能循环
        var heights = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = Float(y) / Float(size)
            for x in 0..<size {
                let u = Float(x) / Float(size)
                let base = tileNoise(u * 16, v * 16, period: 16)
                let mid = tileNoise(u * 32, v * 32, period: 32)
                let fine = tileNoise(u * 64, v * 64, period: 64)
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

    // MARK: 周期值噪声

    private static func hash(_ x: Int, _ y: Int) -> Float {
        var h = UInt32(bitPattern: Int32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= (h >> 16)
        return Float(h % 65_536) / 65_535.0
    }

    private static func tileNoise(_ x: Float, _ y: Float, period: Int) -> Float {
        let mask = period - 1
        let xi = Int(floor(x))
        let yi = Int(floor(y))
        let xf = x - floor(x)
        let yf = y - floor(y)

        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)

        let x0 = xi & mask
        let y0 = yi & mask
        let x1 = (xi + 1) & mask
        let y1 = (yi + 1) & mask

        let a = hash(x0, y0)
        let b = hash(x1, y0)
        let c = hash(x0, y1)
        let d = hash(x1, y1)

        return a * (1 - u) * (1 - v)
            + b * u * (1 - v)
            + c * (1 - u) * v
            + d * u * v
    }

    private static func clamp(_ v: Float) -> Float {
        min(max(v, 0), 255)
    }
}
