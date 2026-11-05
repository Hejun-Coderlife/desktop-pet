import Foundation
import CoreGraphics
import SceneKit

/// 角色的一帧姿势。渲染层只认这个结构，不认状态机。
/// 以后换成 Mixamo 的 .usdz / .dae 时，只要写一个新的 `PetRig` 实现，
/// 把这几个字段映射到骨骼旋转即可，动画逻辑不用动。
struct Pose {
    /// 脚底在屏幕上的位置（窗口坐标，点）
    var feet: CGPoint = .zero
    /// 1 朝右，-1 朝左
    var facing: CGFloat = 1

    /// 整体压扁/拉伸（1 = 正常，<1 压扁）
    var squashY: CGFloat = 1
    /// 身体上下起伏
    var bob: CGFloat = 0
    /// 身体前倾（弧度，正 = 朝右倒）
    var bodyLean: CGFloat = 0

    /// 头部三个轴
    var headPitch: CGFloat = 0
    var headYaw: CGFloat = 0
    var headTilt: CGFloat = 0

    /// 四肢摆动（弧度）
    var armLeft: CGFloat = 0
    var armRight: CGFloat = 0
    var legLeft: CGFloat = 0
    var legRight: CGFloat = 0

    /// 0 = 睁眼，1 = 闭眼
    var blink: CGFloat = 0
}

/// 角色渲染抽象：第一期用 SceneKit 基础形体实现，第二期可换模型实现
protocol PetRig: AnyObject {
    /// 挂到场景里的根节点
    var node: SCNNode { get }
    /// 角色高度（点），用于窗口取景和点击判定
    var pixelHeight: CGFloat { get }
    /// 应用一帧姿势
    func apply(_ pose: Pose)
    /// 眼神方向（-1…1，屏幕坐标方向）。不需要眼神的实现可以不管
    func setGaze(_ direction: CGPoint)
}

extension PetRig {
    func setGaze(_ direction: CGPoint) {}
}
