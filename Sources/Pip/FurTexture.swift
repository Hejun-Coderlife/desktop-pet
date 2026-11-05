import Foundation
import CoreGraphics

/// 程序生成可平铺的「绒毛」法线贴图（值噪声 → 高度场 → 法线）
/// 90 像素高的角色用不上真正的毛发几何，法线贴图 + 柔和光照就够读出绒感了。
/// 两件事必须做对：噪声要周期（否则平铺出现接缝），噪声要沿竖直方向拉长（否则像疙瘩不像毛）。
enum FurTexture {

    private static var cached: CGImage?

    static var shared: CGImage? {
        if let cached { return cached }
        cached = makeNormalMap(size: 512, strength: 2.4)
        return cached
    }

    static func makeNormalMap(size: Int, strength: Float) -> CGImage? {
        // 三倍频，横向 4 倍于纵向 → 毛丝是竖着的长条；周期都是 2 的幂，按位与就能循环
        let octaves: [(freqU: Float, freqV: Float, periodU: Int, periodV: Int, weight: Float)] = [
            (32, 8, 32, 8, 0.5),
            (64, 16, 64, 16, 0.32),
            (128, 32, 128, 32, 0.18)
        ]

        var heights = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = Float(y) / Float(size)
            for x in 0..<size {
                let u = Float(x) / Float(size)
                var height: Float = 0
                for octave in octaves {
                    height += octave.weight * tileNoise(u * octave.freqU, v * octave.freqV,
                                                        periodX: octave.periodU, periodY: octave.periodV)
                }
                heights[y * size + x] = height
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

    private static func tileNoise(_ x: Float, _ y: Float, periodX: Int, periodY: Int) -> Float {
        let maskX = periodX - 1
        let maskY = periodY - 1
        let xi = Int(floor(x))
        let yi = Int(floor(y))
        let xf = x - floor(x)
        let yf = y - floor(y)

        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)

        let x0 = xi & maskX
        let y0 = yi & maskY
        let x1 = (xi + 1) & maskX
        let y1 = (yi + 1) & maskY

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
