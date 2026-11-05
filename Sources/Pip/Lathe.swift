import Foundation
import SceneKit

/// 旋转成形（lathe）：把一条 (高度, 半径) 轮廓线绕 Y 轴转一圈，生成光滑的整块几何体。
/// 身体、兜帽这类「一口钟」的造型用它，比堆球体干净——不会在两个球的相交处留下硬折痕。
enum Lathe {

    /// - Parameter profile: 从下到上的 (y, 半径)，首尾半径应为 0
    static func node(profile: [(y: CGFloat, r: CGFloat)],
                     segments: Int,
                     material: SCNMaterial) -> SCNNode {
        let rows = profile.count
        let cols = segments + 1            // 多一列收口，让 UV 接缝对齐
        let height = max(profile.last!.y - profile.first!.y, 0.001)

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        positions.reserveCapacity(rows * cols)
        normals.reserveCapacity(rows * cols)
        uvs.reserveCapacity(rows * cols)

        for i in 0..<rows {
            let point = profile[i]
            let previous = profile[max(i - 1, 0)]
            let next = profile[min(i + 1, rows - 1)]

            // 轮廓切线 → 朝外的法线（在 (半径, 高度) 平面里转 90°）
            let dy = next.y - previous.y
            let dr = next.r - previous.r
            var normalY = -dr
            var normalR = dy
            let length = sqrt(normalY * normalY + normalR * normalR)
            if length > 0.0001 {
                normalY /= length
                normalR /= length
            } else {
                normalY = 1
                normalR = 0
            }

            for j in 0...segments {
                let angle = CGFloat(j) / CGFloat(segments) * 2 * .pi
                let cosA = cos(angle)
                let sinA = sin(angle)
                positions.append(SCNVector3(point.r * cosA, point.y, point.r * sinA))
                normals.append(SCNVector3(normalR * cosA, normalY, normalR * sinA))
                uvs.append(CGPoint(x: CGFloat(j) / CGFloat(segments),
                                   y: (point.y - profile[0].y) / height))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((rows - 1) * segments * 6)
        for i in 0..<(rows - 1) {
            for j in 0..<segments {
                let a = UInt32(i * cols + j)
                let b = a + 1
                let c = a + UInt32(cols)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: positions),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs)
            ],
            elements: [
                SCNGeometryElement(indices: indices, primitiveType: .triangles)
            ])
        geometry.materials = [material]
        geometry.firstMaterial?.isDoubleSided = false
        return SCNNode(geometry: geometry)
    }
}
