import Foundation
import SceneKit

/// 沿一串点扫出一根等粗的圆管，两端是半球圆头——用来做「绣线」嘴巴这类细长曲线。
/// （以前用一串小球拼，放大后能看到珠子。）
enum Tube {

    static func node(points: [SCNVector3], radius: CGFloat, sides: Int = 10, material: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        guard points.count >= 2 else { return root }

        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var indices: [UInt32] = []

        func sub(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
        func norm(_ v: SCNVector3) -> SCNVector3 {
            let l = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            return l > 0 ? SCNVector3(v.x / l, v.y / l, v.z / l) : SCNVector3(1, 0, 0)
        }
        func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        }

        let n = points.count
        for i in 0..<n {
            let prev = points[max(i - 1, 0)]
            let next = points[min(i + 1, n - 1)]
            let t = norm(sub(next, prev))
            // 曲线基本在 XY 平面里：用 Z 轴和切线构造截面
            var u = cross(t, SCNVector3(0, 0, 1))
            u = norm(u)
            let w = norm(cross(u, t))
            for s in 0..<sides {
                let a = CGFloat(s) / CGFloat(sides) * 2 * .pi
                let dir = SCNVector3(u.x * cos(a) + w.x * sin(a),
                                     u.y * cos(a) + w.y * sin(a),
                                     u.z * cos(a) + w.z * sin(a))
                positions.append(SCNVector3(points[i].x + dir.x * radius,
                                            points[i].y + dir.y * radius,
                                            points[i].z + dir.z * radius))
                normals.append(dir)
            }
        }
        for i in 0..<(n - 1) {
            for s in 0..<sides {
                let a = UInt32(i * sides + s)
                let b = UInt32(i * sides + (s + 1) % sides)
                let c = a + UInt32(sides)
                let d = b + UInt32(sides)
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        g.materials = [material]
        root.addChildNode(SCNNode(geometry: g))

        // 圆头
        for p in [points.first!, points.last!] {
            let cap = SCNSphere(radius: radius)
            cap.segmentCount = 12
            cap.materials = [material]
            let c = SCNNode(geometry: cap)
            c.position = p
            root.addChildNode(c)
        }
        return root
    }
}
