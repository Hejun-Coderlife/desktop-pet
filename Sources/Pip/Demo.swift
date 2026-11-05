import AppKit
import SceneKit
import Metal

/// 产品演示视频：在一个「假桌面」里按剧本表演，逐帧渲染成 PNG（1920×1080，2 倍超采样），
/// 再用 ffmpeg 合成。不碰真实桌面，不会拍到任何私人内容。
///
/// 用法：Pip --demo 输出目录 [起始秒 结束秒]
/// 剧本是按时间写死的；为了让眼神平滑、抛出去的物理连续，每次都从 0 秒开始模拟，只渲染指定区间。
enum Demo {

    static let fps = 30.0
    static let duration = 41.0
    static let W: CGFloat = 960, H: CGFloat = 540      // 舞台大小（点）
    static let outW = 1920, outH = 1080
    static let ground: CGFloat = 56                     // 程序坞上沿（真实屏幕 visibleFrame.minY）

    // 窗口（第 5 段）
    static let winW: CGFloat = 400, winH: CGFloat = 220
    static let winCX: CGFloat = 640, winTop: CGFloat = 330

    /// 不要字幕讲解：功能一看就懂，只留背景音乐（片尾保留产品名）
    static let captions: [(Double, Double, String)] = []

    // MARK: 状态

    struct Pet {
        var x: CGFloat = 120, y: CGFloat = Demo.ground
        var vx: CGFloat = 0, vy: CGFloat = 0
        var state: PetState = .walk
        var stateStart = 0.0
        var facing: CGFloat = 1
        var walkPhase: CGFloat = 0
        var sign: String?
        var grabVelocity = CGVector.zero
        var support: CGFloat = Demo.ground
    }

    enum CursorStyle { case arrow, open, closed }

    // MARK: 入口

    static func run(dir: String, from: Double?, to: Double?) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Outfit.override = Outfit.none
        let built = SceneFactory.makeScene(viewportSize: CGSize(width: W, height: H))
        let scene = built.scene
        let rig = built.rig
        let camera = built.camera

        // 假桌面
        // 真实桌面：壁纸层 + 程序坞层分别截图（不含任何窗口），去掉了 Clash、WPS 和最小化窗口缩略图，
        // 取真实屏幕底部正中 960×540 点。没有素材时退回程序画的假桌面。
        // 真实桌面不进 SceneKit（它会再做一次色彩转换，壁纸变暗变艳）：Pip 渲染在透明层上，合成时盖到原图上
        if realDesktop == nil {
            scene.rootNode.addChildNode(plane(backgroundImage(), w: W, h: H, at: SCNVector3(W / 2, H / 2, -400), order: -20))
            scene.rootNode.addChildNode(plane(dockImage(), w: 520, h: 62, at: SCNVector3(W / 2, 31, -380), order: -18))
        }
        let window = plane(windowImage(), w: winW, h: winH, at: SCNVector3(winCX, winTop - winH / 2, -300), order: -10)
        scene.rootNode.addChildNode(window)

        // 鼠标
        let cursors: [CursorStyle: (SCNNode, NSPoint, NSSize)] = [
            .arrow: arrowCursorNode(), .open: cursorNode(NSCursor.openHand), .closed: cursorNode(NSCursor.closedHand)
        ]
        for (_, c) in cursors { scene.rootNode.addChildNode(c.0) }

        // 音符
        var notes: [SCNNode] = []
        for (i, s) in ["♪", "♫", "♪", "♬"].enumerated() {
            let img = PipRig.textImage(s, fontSize: 90, color: NSColor.hex([0xE88AA0, 0x8AA8E8, 0xE8B86A, 0x9AD0A8][i]),
                                       size: CGSize(width: 110, height: 110))
            let n = plane(img, w: 30, h: 30, at: SCNVector3(0, 0, 60), order: 5)
            scene.rootNode.addChildNode(n)
            notes.append(n)
        }

        // 结尾的三只换装 Pip
        var outfitRigs: [PipRig] = []
        for o in [Outfit.halloween, .christmas, .newyear] {
            Outfit.override = o
            let r = PipRig()
            r.node.isHidden = true
            scene.rootNode.addChildNode(r.node)
            outfitRigs.append(r)
        }
        Outfit.override = nil
        var outfitShadows: [SCNNode] = []
        for _ in 0..<3 {
            let s = SceneFactory.makeShadowNode()
            s.isHidden = true
            scene.rootNode.addChildNode(s)
            outfitShadows.append(s)
        }

        let renderer = FrameRenderer(scene: scene, camera: camera, width: outW * 2, height: outH * 2)
        var pet = Pet()
        var gaze = CGPoint.zero
        var lastCursor = CGPoint(x: 860, y: 430)
        // 抛出 / 掉落的物理
        var flying = false

        let frames = Int(duration * fps)
        let startFrame = Int((from ?? 0) * fps), endFrame = min(frames, Int((to ?? duration) * fps))
        let started = Date()

        for f in 0..<frames {
            let t = Double(f) / fps
            let dt = CGFloat(1 / fps)
            func set(_ s: PetState) { if pet.state != s { pet.state = s; pet.stateStart = t } }

            var cursor: (CGPoint, CursorStyle)? = nil
            var winAlpha: CGFloat = 0, winOffset: CGFloat = 0, winScale: CGFloat = 1
            var dancing = false
            var ending = false

            // —— 物理（被甩出去、从窗口掉下来）——
            func physics() {
                pet.vy -= PetWorld.gravity * dt
                pet.vx *= max(0, 1 - PetWorld.airDrag * dt)
                pet.x += pet.vx * dt
                pet.y += pet.vy * dt
                if pet.x < 40 { pet.x = 40; pet.vx = abs(pet.vx) * 0.45 }
                if pet.x > W - 40 { pet.x = W - 40; pet.vx = -abs(pet.vx) * 0.45 }
                if pet.y <= ground && pet.vy <= 0 {
                    pet.y = ground; pet.vx = 0; pet.vy = 0; flying = false
                    pet.support = ground
                    set(.landing)
                }
            }

            switch t {
            case ..<3.6:
                // 走进来
                set(.walk)
                pet.facing = 1
                pet.x = 120 + (400 - 120) * CGFloat(t / 3.6)
                pet.walkPhase += dt * 8.6 * 1.6

            case ..<7.6:
                set(.idle)
                cursor = (path(t, 3.6, 7.6, [CGPoint(x: 880, y: 440), CGPoint(x: 640, y: 300), CGPoint(x: 290, y: 260),
                                             CGPoint(x: 560, y: 235), CGPoint(x: 470, y: 200)]), .arrow)

            case ..<11.2:
                let u = t - 7.6
                let target = CGPoint(x: pet.x + 18 * CGFloat(sin(u * 7)), y: 150 + 4 * CGFloat(sin(u * 14)))
                let p = u < 0.5 ? lerp(CGPoint(x: 470, y: 200), CGPoint(x: pet.x, y: 150), ease(u / 0.5)) : target
                cursor = (p, .open)
                if u > 0.9 { set(.petted) } else { set(.idle) }

            case ..<16.0:
                let u = t - 11.2
                if u < 0.3 {
                    if pet.state == .petted || pet.state == .idle { set(.idle) }
                    cursor = (CGPoint(x: pet.x, y: 150), .open)
                } else if u < 2.25 {
                    // 拎起来：从头顶往右上拖，再快速一甩
                    let p: CGPoint = u < 2.0
                        ? lerp(CGPoint(x: 400, y: 150), CGPoint(x: 520, y: 380), ease((u - 0.3) / 1.7))
                        : lerp(CGPoint(x: 520, y: 380), CGPoint(x: 640, y: 350), (u - 2.0) / 0.25)
                    cursor = (p, .closed)
                    set(.grabbed)
                    let nx = p.x, ny = max(ground, p.y - 80)
                    let v = CGVector(dx: (nx - pet.x) / dt, dy: (ny - pet.y) / dt)
                    pet.grabVelocity = CGVector(dx: pet.grabVelocity.dx * 0.6 + v.dx * 0.4, dy: pet.grabVelocity.dy * 0.6 + v.dy * 0.4)
                    pet.x = nx; pet.y = ny
                } else {
                    if pet.state == .grabbed {
                        // 松手：带着拖拽速度飞出去（限速，免得出画）
                        var v = pet.grabVelocity
                        let sp = hypot(v.dx, v.dy)
                        if sp > 900 { v = CGVector(dx: v.dx * 900 / sp, dy: v.dy * 900 / sp) }
                        pet.vx = v.dx; pet.vy = v.dy
                        flying = true
                        set(.falling)
                    }
                    if flying { physics() }
                    if pet.state == .landing && t - pet.stateStart > Double(PetWorld.landingDuration) { set(.idle) }
                    let away = min(1, (u - 2.25) / 0.8)
                    if away < 1 { cursor = (lerp(CGPoint(x: 640, y: 350), CGPoint(x: 900, y: 470), ease(away)), .arrow) }
                }

            case ..<23.0:
                let u = t - 16.0
                winAlpha = CGFloat(min(1, u / 0.45))
                if u < 1.0 {
                    if pet.state == .landing && t - pet.stateStart > Double(PetWorld.landingDuration) { set(.idle) }
                    if flying { physics() }
                    if pet.state != .landing && !flying { set(.idle) }
                    pet.facing = 620 > pet.x ? 1 : -1
                } else if u < 1.8 {
                    // 跳上窗口顶：一条抛物线，最后是往下落着踩上去
                    if pet.state != .falling { set(.falling); pet.vx = pet.x }   // 借 vx 存起跳点
                    let k = CGFloat((u - 1.0) / 0.8)
                    let x0 = pet.vx == 0 ? pet.x : pet.vx
                    let h: CGFloat = 95
                    let prevY = pet.y
                    pet.x = x0 + (620 - x0) * k
                    pet.y = ground + (winTop - ground) * k + 4 * h * k * (1 - k)
                    pet.vy = (pet.y - prevY) / dt
                    pet.facing = 620 >= x0 ? 1 : -1
                } else if u < 5.5 {
                    pet.vx = 0
                    pet.support = winTop
                    if pet.state == .falling { pet.y = winTop; pet.x = 620; set(.landing) }
                    if pet.state == .landing && t - pet.stateStart > Double(PetWorld.landingDuration) { set(.perch) }
                    // 鼠标抓住标题栏左右拖一下，Pip 坐在上面跟着走
                    if u >= 2.8 && u < 3.4 {
                        cursor = (lerp(CGPoint(x: 300, y: 470), CGPoint(x: 560, y: winTop - 11), ease((u - 2.8) / 0.6)), .arrow)
                    } else if u >= 3.4 {
                        let d = min(1, (u - 3.5) / 1.4)
                        winOffset = d > 0 ? -130 * CGFloat(sin(.pi * d)) : 0
                        cursor = (CGPoint(x: 560 + winOffset, y: winTop - 11), .arrow)
                        if u > 4.95 {
                            // 移到红色关闭按钮
                            let k = min(1, (u - 4.95) / 0.4)
                            cursor = (lerp(CGPoint(x: 560, y: winTop - 11), CGPoint(x: winCX - winW / 2 + 14, y: winTop - 11), ease(k)), .arrow)
                        }
                    }
                    pet.x = 620 + winOffset
                    pet.y = winTop
                } else {
                    // 点了关闭：窗口缩一下消失，Pip 掉下去
                    let k = min(1, (u - 5.5) / 0.22)
                    winAlpha = 1 - CGFloat(k)
                    winScale = 1 - 0.05 * CGFloat(k)
                    if pet.state == .perch { pet.vx = 0; pet.vy = 0; flying = true; set(.falling) }
                    if flying { physics() }
                    if pet.state == .landing && t - pet.stateStart > Double(PetWorld.landingDuration) { set(.idle) }
                    let away = min(1, (u - 5.6) / 0.7)
                    if away < 1 { cursor = (lerp(CGPoint(x: winCX - winW / 2 + 14, y: winTop - 11), CGPoint(x: 120, y: 470), ease(away)), .arrow) }
                }

            case ..<27.0:
                set(.dance)
                pet.support = ground
                dancing = true

            case ..<30.5:
                if pet.state != .sign { pet.sign = "喝口水吧 💧"; set(.sign) }

            case ..<35.6:
                pet.sign = nil
                if t < 34.0 { set(.sleep) } else {
                    set(.wake)
                }
                if t > 33.4 {
                    let k = min(1, (t - 33.4) / 0.6)
                    cursor = (lerp(CGPoint(x: 900, y: 420), CGPoint(x: pet.x + 120, y: 210), ease(k)), .arrow)
                }

            default:
                ending = true
            }

            // 眼神跟鼠标（同 Stage.updateLook）
            if let (p, _) = cursor {
                let dx = p.x - pet.x, dy = p.y - (pet.y + 62)
                let engaged = hypot(dx, dy) < 320
                let tx = engaged ? max(-1, min(1, dx / 110)) : 0
                let ty = engaged ? max(-1, min(1, dy / 110)) : 0
                gaze.x += (tx - gaze.x) * 0.25
                gaze.y += (ty - gaze.y) * 0.25
                lastCursor = p
            } else {
                gaze.x *= 0.85; gaze.y *= 0.85
            }

            guard f >= startFrame && f < endFrame else { continue }

            // —— 摆场景 ——
            // 命令行里没有运行循环，隐式事务永远不会提交：所有改动必须包在立即生效的事务里
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            let world = PetWorld(size: CGSize(width: W, height: H), groundY: ground, seed: 7)
            world.preview(state: pet.state, time: CGFloat(t), feet: CGPoint(x: pet.x, y: pet.y),
                          walkPhase: pet.walkPhase, stateTime: CGFloat(t - pet.stateStart),
                          velocity: CGVector(dx: pet.vx, dy: pet.vy), grabVelocity: pet.grabVelocity,
                          sign: pet.sign, facing: pet.facing)
            rig.setGaze(CGPoint(x: gaze.x * pet.facing, y: gaze.y))
            rig.apply(PetAnimator.pose(for: world))
            rig.node.isHidden = ending

            let lift = max(0, pet.y - pet.support)
            let st = min(1, lift / 240)
            let ss = (1 - 0.42 * st)
            let lying = pet.state == .sleep
            built.shadow.isHidden = ending
            built.shadow.position = SCNVector3(pet.x + (lying ? pet.facing * 32 : 0), pet.support + 1.5, 1)
            built.shadow.scale = SCNVector3(ss * (lying ? 1.9 : 1), ss, ss)
            built.shadow.opacity = 1 - 0.75 * st

            window.opacity = winAlpha
            window.isHidden = winAlpha <= 0.001
            window.position = SCNVector3(winCX + winOffset, winTop - winH / 2, -300)
            window.scale = SCNVector3(winScale, winScale, 1)

            for (style, c) in cursors {
                guard let (p, s) = cursor, s == style else { c.0.isHidden = true; continue }
                c.0.isHidden = false
                let k: CGFloat = 1.35
                // 热点对准 p（图片坐标 y 朝下）
                c.0.position = SCNVector3(p.x - c.1.x * k + c.2.width * k / 2, p.y + c.1.y * k - c.2.height * k / 2, 200)
                c.0.scale = SCNVector3(k, k, 1)
            }

            for (i, n) in notes.enumerated() {
                n.isHidden = !dancing
                guard dancing else { continue }
                let ph = (t * 0.6 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                let side: CGFloat = i % 2 == 0 ? -1 : 1
                n.position = SCNVector3(pet.x + side * (46 + CGFloat(ph) * 14), pet.y + 70 + CGFloat(ph) * 70, 60)
                n.opacity = CGFloat(sin(ph * .pi))
                n.eulerAngles.z = CGFloat(sin(t * 3 + Double(i))) * 0.3
            }

            for (i, r) in outfitRigs.enumerated() {
                r.node.isHidden = !ending
                outfitShadows[i].isHidden = !ending
                guard ending else { continue }
                let x: CGFloat = 330 + CGFloat(i) * 150
                let w = PetWorld(size: CGSize(width: W, height: H), groundY: ground, seed: UInt64(20 + i))
                w.preview(state: .idle, time: CGFloat(t + Double(i) * 0.9), feet: CGPoint(x: x, y: ground))
                r.setGaze(CGPoint(x: (480 - x) / 300, y: -0.1))
                r.apply(PetAnimator.pose(for: w))
                outfitShadows[i].position = SCNVector3(x, ground + 1.5, 1)
            }

            let cam = cameraAt(t)
            camera.position = SCNVector3(cam.x, cam.y, 1200)
            camera.camera?.orthographicScale = Double(cam.z)

            SCNTransaction.commit()

            guard let img = renderer.render(), let out = compose(img, t: t) else {
                print("✗ 第 \(f) 帧渲染失败"); exit(1)
            }
            _ = Snapshot.write(image: out, to: String(format: "%@/%05d.png", dir, f))
            if f % 60 == 0 {
                print(String(format: "  %.1f 秒（第 %d 帧），已用 %.0f 秒", t, f, Date().timeIntervalSince(started)))
            }
        }
        print("✓ 渲染完成：\(endFrame - startFrame) 帧 → \(dir)")
        _ = lastCursor
    }

    // MARK: 镜头（中心 x、y，正交半高）

    static func cameraAt(_ t: Double) -> SCNVector3 {
        let full = SCNVector3(W / 2, H / 2, H / 2)
        let keys: [(Double, SCNVector3)] = [
            (0, full), (3.6, full),
            (4.6, SCNVector3(440, 215, 205)), (7.6, SCNVector3(440, 215, 205)),
            (8.4, SCNVector3(405, 160, 135)), (11.0, SCNVector3(405, 160, 135)),
            (11.8, full), (22.6, full),
            (23.4, SCNVector3(610, 175, 175)), (30.3, SCNVector3(610, 175, 175)),
            (31.0, SCNVector3(600, 150, 160)), (35.2, SCNVector3(600, 150, 160)),
            (36.0, SCNVector3(480, 175, 175)), (41, SCNVector3(480, 175, 175)),
        ]
        var a = keys[0], b = keys[keys.count - 1]
        for i in 1..<keys.count where t <= keys[i].0 { a = keys[i - 1]; b = keys[i]; break }
        let k = CGFloat(ease(b.0 > a.0 ? (t - a.0) / (b.0 - a.0) : 1))
        var v = SCNVector3(a.1.x + (b.1.x - a.1.x) * k, a.1.y + (b.1.y - a.1.y) * k, a.1.z + (b.1.z - a.1.z) * k)
        // 画面不能超出假桌面
        let halfH = v.z, halfW = v.z * 16 / 9
        v.x = min(max(v.x, halfW), W - halfW)
        v.y = min(max(v.y, halfH), H - halfH)
        return v
    }

    // MARK: 合成字幕

    static let realDesktop: CGImage? = {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: "video/assets/desktop-crop.png") as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }()

    static func compose(_ img: CGImage, t: Double) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        if let bg = realDesktop {
            // 按当前镜头把真实桌面的对应区域铺满画面
            let cam = cameraAt(t)
            let hh = CGFloat(cam.z), hw = hh * 16 / 9
            let k = CGFloat(outH) / (2 * hh)
            ctx.draw(bg, in: CGRect(x: -(CGFloat(cam.x) - hw) * k, y: -(CGFloat(cam.y) - hh) * k, width: W * k, height: H * k))
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

        for (a, b, text) in captions where t >= a && t <= b {
            let alpha = CGFloat(min(1, (t - a) / 0.3, (b - t) / 0.3))
            let font = NSFont(name: "PingFangSC-Semibold", size: 46) ?? .boldSystemFont(ofSize: 46)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha)]
            let str = NSAttributedString(string: text, attributes: attrs)
            let size = str.size()
            let pill = CGRect(x: (CGFloat(outW) - size.width) / 2 - 34, y: CGFloat(outH) - 92 - size.height - 22,
                              width: size.width + 68, height: size.height + 26)
            NSColor(white: 0.12, alpha: 0.55 * alpha).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            str.draw(at: CGPoint(x: pill.minX + 34, y: pill.minY + 13))
        }

        if t >= 38.4 {
            let alpha = CGFloat(min(1, (t - 38.4) / 0.5))
            let title = NSAttributedString(string: "Pip", attributes: [
                .font: NSFont(name: "PingFangSC-Semibold", size: 150) ?? .boldSystemFont(ofSize: 150),
                .foregroundColor: NSColor.hex(0x5A4A42).withAlphaComponent(alpha)])
            let sub = NSAttributedString(string: "你的桌面毛绒小伙伴", attributes: [
                .font: NSFont(name: "PingFangSC-Regular", size: 48) ?? .systemFont(ofSize: 48),
                .foregroundColor: NSColor.hex(0x7A6A62).withAlphaComponent(alpha)])
            let ts = title.size(), ss = sub.size()
            title.draw(at: CGPoint(x: (CGFloat(outW) - ts.width) / 2, y: 690))
            sub.draw(at: CGPoint(x: (CGFloat(outW) - ss.width) / 2, y: 630))
        }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    // MARK: 小工具

    static func ease(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(k), y: a.y + (b.y - a.y) * CGFloat(k))
    }
    /// 在 t0…t1 之间沿一串点走，每段都缓入缓出
    static func path(_ t: Double, _ t0: Double, _ t1: Double, _ pts: [CGPoint]) -> CGPoint {
        let u = min(max((t - t0) / (t1 - t0), 0), 0.9999) * Double(pts.count - 1)
        let i = Int(u)
        return lerp(pts[i], pts[i + 1], ease(u - Double(i)))
    }

    static func plane(_ image: Any, w: CGFloat, h: CGFloat, at p: SCNVector3, order: Int) -> SCNNode {
        let g = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = order > 0
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        n.renderingOrder = order
        n.castsShadow = false
        return n
    }

    /// NSCursor 的图是多分辨率 / 矢量的，SceneKit 直接用有时是空白（箭头就是）：先画成 4 倍位图
    static func bitmap(_ image: NSImage, scale: CGFloat = 4) -> CGImage? {
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// 命令行进程拿不到系统箭头光标的图（是空的），自己画一个经典黑箭头白描边
    static func arrowCursorNode() -> (SCNNode, NSPoint, NSSize) {
        let size = NSSize(width: 17, height: 25)
        let img = draw(CGSize(width: size.width * 4, height: size.height * 4)) { r in
            let k: CGFloat = 4
            let pts: [(CGFloat, CGFloat)] = [(1.5, 1.5), (1.5, 19.5), (6, 15.5), (9, 22.5), (12, 21.2), (9.2, 14.4), (15, 14.4)]
            let path = NSBezierPath()
            for (i, p) in pts.enumerated() {
                let q = CGPoint(x: p.0 * k, y: r.height - p.1 * k)
                if i == 0 { path.move(to: q) } else { path.line(to: q) }
            }
            path.close()
            path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 2.6 * k; path.stroke()
            NSColor.black.setFill(); path.fill()
        }
        let n = plane(bitmap(img, scale: 1) as Any, w: size.width, h: size.height, at: SCNVector3(0, 0, 200), order: 50)
        n.geometry?.firstMaterial?.readsFromDepthBuffer = false
        n.isHidden = true
        return (n, NSPoint(x: 1.5, y: 1.5), size)
    }

    static func cursorNode(_ c: NSCursor) -> (SCNNode, NSPoint, NSSize) {
        let n = plane(bitmap(c.image) as Any, w: c.image.size.width, h: c.image.size.height, at: SCNVector3(0, 0, 200), order: 50)
        n.geometry?.firstMaterial?.readsFromDepthBuffer = false
        n.isHidden = true
        return (n, c.hotSpot, c.image.size)
    }

    // MARK: 假桌面的图（全部程序画，不用任何真实截图 / App 图标）

    static func draw(_ size: CGSize, _ body: (CGRect) -> Void) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        body(CGRect(origin: .zero, size: size))
        img.unlockFocus()
        return img
    }

    static func backgroundImage() -> NSImage {
        draw(CGSize(width: 1920, height: 1080)) { r in
            NSGradient(colors: [NSColor.hex(0xE9E4F2), NSColor.hex(0xF6E6E1), NSColor.hex(0xE3EEF0)])?.draw(in: r, angle: -35)
            for (x, y, rad, c) in [(300.0, 800.0, 520.0, 0xF3D3DA), (1550.0, 300.0, 600.0, 0xD6E4F5), (1100.0, 950.0, 420.0, 0xF5E3C8)] {
                let g = NSGradient(colors: [NSColor.hex(UInt32(c), alpha: 0.75), NSColor.hex(UInt32(c), alpha: 0)])
                g?.draw(fromCenter: CGPoint(x: x, y: y), radius: 0, toCenter: CGPoint(x: x, y: y), radius: rad, options: [])
            }
        }
    }

    static func menuBarImage() -> NSImage {
        draw(CGSize(width: 1920, height: 32)) { r in
            NSColor(white: 1, alpha: 0.55).setFill(); r.fill()
            NSColor(white: 0.25, alpha: 0.55).setFill()
            for (i, w) in [44, 70, 60, 56, 64].enumerated() {
                NSBezierPath(roundedRect: CGRect(x: 30 + CGFloat(i) * 96, y: 11, width: CGFloat(w), height: 10), xRadius: 5, yRadius: 5).fill()
            }
            for i in 0..<4 {
                NSBezierPath(ovalIn: CGRect(x: 1700 + CGFloat(i) * 46, y: 8, width: 16, height: 16)).fill()
            }
        }
    }

    static func dockImage() -> NSImage {
        draw(CGSize(width: 1040, height: 124)) { r in
            let box = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: 34, yRadius: 34)
            NSColor(white: 1, alpha: 0.42).setFill(); box.fill()
            NSColor(white: 1, alpha: 0.7).setStroke(); box.lineWidth = 2; box.stroke()
            let colors: [UInt32] = [0x9BC4F0, 0xF2B7C6, 0xB8E0C2, 0xF5D58E, 0xC9B8F0, 0xF0A890, 0x9FDCE0, 0xE6C3A8, 0xB5C2D8]
            let n = colors.count, side: CGFloat = 88, gap: CGFloat = 20
            let x0 = (r.width - CGFloat(n) * side - CGFloat(n - 1) * gap) / 2
            for (i, c) in colors.enumerated() {
                let rect = CGRect(x: x0 + CGFloat(i) * (side + gap), y: 18, width: side, height: side)
                let g = NSGradient(colors: [NSColor.hex(c), NSColor.hex(c).blended(withFraction: 0.35, of: .white)!])
                g?.draw(in: NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20), angle: 90)
            }
        }
    }

    static func windowImage() -> NSImage {
        draw(CGSize(width: winW * 2, height: winH * 2)) { r in
            let shape = NSBezierPath(roundedRect: r.insetBy(dx: 2, dy: 2), xRadius: 22, yRadius: 22)
            NSColor(white: 0.995, alpha: 1).setFill(); shape.fill()
            NSColor(white: 0.82, alpha: 1).setStroke(); shape.lineWidth = 2; shape.stroke()
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSColor(white: 0.945, alpha: 1).setFill()
            CGRect(x: 0, y: r.height - 48, width: r.width, height: 48).fill()
            NSGraphicsContext.restoreGraphicsState()
            for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
                NSColor.hex(UInt32(c)).setFill()
                NSBezierPath(ovalIn: CGRect(x: 20 + CGFloat(i) * 26, y: r.height - 32, width: 16, height: 16)).fill()
            }
            NSColor(white: 0.86, alpha: 1).setFill()
            for (i, w) in [520, 640, 580, 300, 610, 470].enumerated() {
                NSBezierPath(roundedRect: CGRect(x: 44, y: r.height - 100 - CGFloat(i) * 52, width: CGFloat(w), height: 18),
                             xRadius: 9, yRadius: 9).fill()
            }
        }
    }
}

/// 复用同一套 Metal 资源逐帧渲染（Snapshot.render 每次都新建设备，逐帧用太慢）
final class FrameRenderer {
    let device: MTLDevice
    let renderer: SCNRenderer
    let queue: MTLCommandQueue
    let texture: MTLTexture
    let buffer: MTLBuffer
    let width: Int, height: Int

    init(scene: SCNScene, camera: SCNNode, width: Int, height: Int) {
        device = MTLCreateSystemDefaultDevice()!
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        queue = device.makeCommandQueue()!
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        texture = device.makeTexture(descriptor: d)!
        buffer = device.makeBuffer(length: width * height * 4, options: .storageModeShared)!
        self.width = width; self.height = height
    }

    func render() -> CGImage? {
        guard let cb = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, Demo.realDesktop == nil ? 1 : 0)
        renderer.render(atTime: 0, viewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: cb, passDescriptor: pass)
        guard let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: width * 4, destinationBytesPerImage: width * height * 4)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        let data = Data(bytes: buffer.contents(), count: width * height * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
