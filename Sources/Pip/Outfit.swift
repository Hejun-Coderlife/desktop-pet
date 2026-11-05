import AppKit
import SceneKit

/// 节日装扮：按日期自动戴上。调试可用环境变量 PIP_OUTFIT=halloween / christmas / newyear / none
enum Outfit: String {
    case none, halloween, christmas, newyear

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "outfitsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "outfitsEnabled") }
    }

    static func current(date: Date = Date()) -> Outfit {
        if let forced = ProcessInfo.processInfo.environment["PIP_OUTFIT"], let o = Outfit(rawValue: forced) { return o }
        guard enabled else { return .none }
        let cal = Calendar(identifier: .gregorian)
        let m = cal.component(.month, from: date), d = cal.component(.day, from: date)
        if (m == 10 && d >= 24) || (m == 11 && d <= 1) { return .halloween }
        if m == 12 && d >= 15 && d <= 26 { return .christmas }
        // 春节：农历腊月二十三 ～ 正月十五
        let lunar = Calendar(identifier: .chinese)
        let lm = lunar.component(.month, from: date), ld = lunar.component(.day, from: date)
        let leap = lunar.dateComponents([.month], from: date).isLeapMonth ?? false
        if !leap && ((lm == 12 && ld >= 23) || (lm == 1 && ld <= 15)) { return .newyear }
        return .none
    }

    /// headGroup 原点 = 脸中心（身体坐标 y≈60、z≈18）；头顶毛尖大约在本地 y≈31、z≈-17
    func attach(to head: SCNNode, body: SCNNode) {
        switch self {
        case .none: return
        case .halloween: head.addChildNode(pumpkinHat())
        case .christmas: head.addChildNode(santaHat())
        case .newyear: body.addChildNode(scarf())
        }
    }

    private func mat(_ hex: UInt32, shiny: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = shiny ? .blinn : .lambert
        m.diffuse.contents = NSColor.hex(hex)
        if shiny { m.specular.contents = NSColor(white: 0.35, alpha: 1) }
        return m
    }

    private func pumpkinHat() -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(0, 30, -14)
        root.eulerAngles = SCNVector3(-0.15, 0, 0.12)
        // 南瓜：几瓣压扁的球拼成一圈，比单个球更像南瓜
        let orange = mat(0xF08A24, shiny: true)
        for i in 0..<6 {
            let a = CGFloat(i) / 6 * 2 * .pi
            let lobe = SCNNode(geometry: SCNSphere(radius: 8))
            lobe.geometry?.materials = [orange]
            lobe.scale = SCNVector3(0.75, 0.82, 0.75)
            lobe.position = SCNVector3(cos(a) * 5.5, 0, sin(a) * 5.5)
            root.addChildNode(lobe)
        }
        let stem = SCNNode(geometry: SCNCylinder(radius: 1.6, height: 5))
        stem.geometry?.materials = [mat(0x4E7A35)]
        stem.position = SCNVector3(0, 7.5, 0)
        stem.eulerAngles = SCNVector3(0, 0, 0.25)
        root.addChildNode(stem)
        let leaf = SCNNode(geometry: SCNSphere(radius: 3))
        leaf.geometry?.materials = [mat(0x6A9E45)]
        leaf.scale = SCNVector3(1.3, 0.3, 0.8)
        leaf.position = SCNVector3(3, 7, 1)
        root.addChildNode(leaf)
        return root
    }

    private func santaHat() -> SCNNode {
        let root = SCNNode()
        root.position = SCNVector3(0, 27, -14)
        root.eulerAngles = SCNVector3(-0.2, 0, -0.35)
        let cone = SCNNode(geometry: SCNCone(topRadius: 0.5, bottomRadius: 13, height: 24))
        cone.geometry?.materials = [mat(0xD7263D)]
        cone.position = SCNVector3(0, 12, 0)
        root.addChildNode(cone)
        let brim = SCNNode(geometry: SCNTorus(ringRadius: 12.5, pipeRadius: 3.4))
        brim.geometry?.materials = [mat(0xF8F4EE)]
        root.addChildNode(brim)
        let pom = SCNNode(geometry: SCNSphere(radius: 3.6))
        pom.geometry?.materials = [mat(0xF8F4EE)]
        pom.position = SCNVector3(0, 24.5, 0)
        root.addChildNode(pom)
        return root
    }

    private func scarf() -> SCNNode {
        let root = SCNNode()
        let red = mat(0xC8102E)
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 30.5, pipeRadius: 6.8))
        ring.geometry?.materials = [red]
        ring.position = SCNVector3(0, 33, 0)
        ring.scale = SCNVector3(1, 0.85, 1)
        root.addChildNode(ring)
        let tail = SCNNode(geometry: SCNBox(width: 11, height: 22, length: 4, chamferRadius: 2))
        tail.geometry?.materials = [red]
        tail.position = SCNVector3(13, 21, 35)
        tail.eulerAngles = SCNVector3(0.1, 0, 0.18)
        root.addChildNode(tail)
        let tassel = SCNNode(geometry: SCNBox(width: 11, height: 3.5, length: 4.2, chamferRadius: 0.8))
        tassel.geometry?.materials = [mat(0xF2C14E)]
        tassel.position = SCNVector3(15, 9.5, 35.3)
        tassel.eulerAngles = SCNVector3(0.1, 0, 0.18)
        root.addChildNode(tassel)
        return root
    }
}
