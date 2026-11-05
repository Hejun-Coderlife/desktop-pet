# Pip 桌面精灵 · 第一期交付说明

日期：2026-11-05
位置：`/Users/hejun/Projects/desktop-pet`

一只站在屏幕底部、在程序坞上沿走来走去的 Q 版小人。可以拎起来甩出去，它会自己掉回来。
角色叫 **Pip**，原创造型（薄荷绿身体 + 奶油肚皮 + 头顶小芽），不是戴红帽子的男孩。

---

## 一、做到哪了（第一期功能全部完成）

| 功能 | 状态 |
|---|---|
| 透明舞台窗口（覆盖主屏、无边框、不抢焦点、程序坞之上） | 完成 |
| 所有桌面空间显示（canJoinAllSpaces + stationary + fullScreenNone） | 完成 |
| 鼠标穿透（每帧判断是否在小人身上） | 完成 |
| 地面 = 主屏 visibleFrame 底边，程序坞隐藏/换边会更新 | 完成 |
| 程序化建模的 Q 版小人（约 90 点高，SceneKit 基础形体） | 完成 |
| 走路 / 发呆（呼吸、眨眼、转头）/ 被拎起乱晃 / 下落 / 落地压扁回弹 | 完成 |
| 行为状态机：闲逛、随机走路或站立、撞边掉头 | 完成 |
| 拎起跟手、松手按速度抛出、重力下落、左右边缘反弹、落地回弹 | 完成 |
| 菜单栏图标：显示/隐藏、暂停、退出 | 完成 |
| 静态 10fps / 移动 30fps；被遮挡时停止渲染 | 完成 |
| 全屏 App 时自动隐藏，退出全屏恢复 | 完成 |
| 不联网、不申请任何系统权限、不开机自启 | 完成（无 entitlements、无登录项） |

---

## 二、代码结构

```
Sources/Pip/
  main.swift           入口：参数分发（--selftest / --snapshot / --posesheet / --smoke / --windowcheck）
  AppDelegate.swift    启动 Stage 和菜单栏
  Stage.swift          透明窗口 + 主循环 + 鼠标 + 帧率 + 全屏/遮挡 + 环境变化
  PetWorld.swift       纯逻辑：位置、速度、状态机、物理（不依赖 AppKit，可离屏跑）
  PetAnimator.swift    世界状态 → 一帧姿势（纯函数）
  Pose.swift           姿势结构 + PetRig 协议（换模型的口子）
  PipRig.swift         用 SceneKit 基础形体拼出来的角色
  SceneFactory.swift   场景、正交相机、灯光、脚底阴影
  MenuBarController.swift 菜单栏
  SelfTest.swift       离屏状态机自检
  Snapshot.swift       离屏渲染 PNG / 五连姿势对照图
Resources/Info.plist   LSUIElement=true
package.sh             编译 → 组装 dist/Pip.app → 安装到 /Applications
```

**坐标系**：窗口左下角为原点，单位是「点」，y 向上。正交相机让 1 世界单位 = 1 屏幕点，
所以 `PetWorld.position` 直接就是屏幕坐标，不需要换算。

**换模型的接口**：`Pose.swift` 里的 `PetRig` 协议（`node` / `pixelHeight` / `apply(_:)`）。
以后接 Mixamo 的 .usdz 或 .dae，只要新写一个类加载模型、把 `Pose` 的字段映射到骨骼旋转，
`PetWorld` 和 `PetAnimator` 一行都不用动。角色尺寸若变化，改 `PipRig.pixelHeight`
和 `PetWorld.characterHeight / halfWidth` 即可（点击判定和物理都用这两个值）。

---

## 三、怎么编译、打包、验证

```bash
cd /Users/hejun/Projects/desktop-pet

swift build                 # 调试编译
./.build/debug/Pip --selftest            # 状态机自检，最后一行 PASS / FAIL
./.build/debug/Pip --snapshot /tmp/pip.png   # 渲染一张站立 PNG（透明背景）
./.build/debug/Pip --posesheet /tmp/poses.png  # 五连姿势对照图（开发自用）
./.build/debug/Pip --smoke               # 跑 3 秒更新管线，不显示窗口
./.build/debug/Pip --windowcheck         # 打印窗口层级/地面/点击区域等配置
./package.sh                # release 编译 + 打包 + 安装到 /Applications/Pip.app
```

`package.sh` 会用 ad-hoc 签名（`codesign --sign -`）。没有开发者证书也能在本机运行。

调参入口：
- 手感（重力、速度、反弹、最大抛速）：`PetWorld.swift` 顶部的静态常量
- 动画幅度与节奏：`PetAnimator.swift`
- 造型、配色、比例：`PipRig.swift` 的 `build()` 和 `PipPalette`
- 帧率、全屏检测阈值：`Stage.swift`

---

## 四、验证情况

**已用命令行验证：**
- `swift build` 通过，无警告
- `--selftest`：600 步（10 秒）模拟，含两次拎起抛出（其中一次狠甩撞左墙），
  逐帧检查「不穿地 / 不出屏」，并检查状态序列与撞墙反弹 → **PASS**
- `--snapshot`：离屏渲染成功，四角 alpha 全 0（背景真透明），角色包围盒正常
- `--posesheet`：五种状态姿势目视检查过（走路摆手摆腿、被拎起四肢乱晃、落地压扁）
- `--windowcheck`：窗口层级 21（程序坞 20 / 菜单栏 24）、`isOpaque=false`、
  `canBecomeKey=false`、collectionBehavior 含 canJoinAllSpaces+stationary+fullScreenNone、
  地面 y=72（当前程序坞高度）、相机正交高度 = 窗口高一半（1:1 映射）
- `--smoke`：真实屏幕下跑 3 秒更新管线，地面 72、状态推进正常

**没验证（需要你在屏幕上实际看）：**
- 窗口真的浮在程序坞之上、真的完全透明、点桌面/程序坞/其它 App 完全不受影响
- 拎起来的手感、抛出去的弧线、落地压扁的观感
- 菜单栏三项的实际点击效果
- 切到全屏 App 时是否自动消失、退出后是否恢复
- 多显示器、程序坞换到左右两侧的行为
- 长时间运行的 CPU / 内存占用（预期的静态开销很低，但没测）

---

## 五、已知问题 / 取舍

1. **只覆盖主屏**（按需求）。副屏上没有小人。
2. **点击判定是矩形包围盒**，不是像素级命中：挥手或抬腿时，手/脚边缘几像素可能点不到；
   被判定的矩形比角色略大（四周各 5 点）。
3. **全屏检测靠窗口尺寸**（宽高都 ≥ 屏幕尺寸就算全屏）。个别 App 的全屏窗口若没有占满整屏
   （比如带边框的分屏），可能不会被判定为全屏。
4. **遮挡检测对全屏透明窗口不一定准**：`occlusionState` 在透明窗口上可能一直报 visible，
   那样就退化成「不暂停渲染」，不影响正确性，只影响省电。
5. **Mission Control / 调度中心**里可能会看到一个空的透明窗口轮廓，因为窗口本身确实占满全屏。
   要彻底避免需要改成多窗口或分块窗口，第一期没做。
6. **拖到屏幕外**：拖动时位置会被夹在屏幕范围内，多屏环境下不能拖到副屏。
7. **落地后不滑行**：水平速度直接清零，没有摩擦滑步。
8. **没有 App 图标**：菜单栏用的是系统符号 `pawprint.fill`；`Pip.app` 自身没有 icns。
9. 动画是逐帧写节点变换实现的，没有用 SCNAction，也没有用骨骼动画——这是为「以后换模型」留的余地，
   但也意味着换模型时必须实现 `PetRig`。

---

## 六、第二期计划（本期未做，仅供接口对齐）

目标：文件被拖进废纸篓时，小人跑过去把文件捡回来扔回桌面。

**要申请的权限**（缺一不可，都需要用户在系统设置里手动开）：
- 辅助功能（Accessibility）：模拟移动/拖拽、读取其它 App 的 UI
- 完全磁盘访问（Full Disk Access）：读写 `~/.Trash`
- 自动化 / 控制访达（Apple Events → Finder）：调用访达移动文件

**必须有的安全设计：**
- **暂停开关**：菜单栏里一个显眼的「停止看护文件」，一键停掉所有自动动作
- **排除名单**：按文件名 / 后缀 / 路径前缀排除，命中就完全不管
- **只移动，绝不删除**：程序里不出现任何 `removeItem` / `trashItem` 调用；
  所有操作都是「从 ~/.Trash 移到桌面」，失败就保持原样并记日志
- **同名冲突**：目标桌面已存在同名文件时，自动改名为 `文件名 (1).ext`，不覆盖
- **操作日志**：每次移动记录时间、原路径、新路径，方便事后核对和撤销
- **默认关闭**：装完不自动启用，用户明确打开才开始看护

**技术路径（初步）：** 用 FSEvents 或 DispatchSource 监听 `~/.Trash` 目录；
或轮询 `~/Library/Application Support/...`。检测到新文件后，通知 `PetWorld` 切到
「跑去捡东西」状态（第二期新增状态），用辅助功能模拟拖拽，或用 `FileManager` 直接移动
（后者更稳，但用户提到要「控制访达」，两种可并存：优先直接移动，失败再走 UI 自动化）。

---

## 七、提交历史说明

第一次提交是「第一期主体」这一整块（因为代码是同时写出来再一起验证的），
之后每改一个功能/修一个问题都单独提交。
