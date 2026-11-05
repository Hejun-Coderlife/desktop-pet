import AppKit

let cliArguments = CommandLine.arguments

// 离屏自检：不开窗口，跑 10 秒状态机
if cliArguments.contains("--selftest") {
    let passed = SelfTest.run()
    exit(passed ? 0 : 1)
}

// 离屏渲染一张透明 PNG
if let index = cliArguments.firstIndex(of: "--snapshot") {
    let path = index + 1 < cliArguments.count ? cliArguments[index + 1] : "/tmp/pip.png"
    Snapshot.run(outputPath: path)
    exit(0)
}

// 演示视频：逐帧渲染到目录（--demo 目录 [起始秒 结束秒]）
if let index = cliArguments.firstIndex(of: "--demo") {
    let dir = index + 1 < cliArguments.count ? cliArguments[index + 1] : "/tmp/pip-demo"
    let from = index + 2 < cliArguments.count ? Double(cliArguments[index + 2]) : nil
    let to = index + 3 < cliArguments.count ? Double(cliArguments[index + 3]) : nil
    Demo.run(dir: dir, from: from, to: to)
    exit(0)
}

// 五种状态姿势对照图（开发自用）
if let index = cliArguments.firstIndex(of: "--posesheet") {
    let path = index + 1 < cliArguments.count ? cliArguments[index + 1] : "/tmp/pip-poses.png"
    Snapshot.runSheet(outputPath: path)
    exit(0)
}

// 冒烟测试：不显示窗口，跑 3 秒更新管线
if cliArguments.contains("--smoke") {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let stage = Stage()
    print("Pip 冒烟测试（不显示窗口，跑 3 秒更新管线）")
    print(stage.smokeTest(seconds: 3))
    exit(0)
}

// 窗口配置自检（不显示窗口，只打印属性）
if cliArguments.contains("--windowcheck") {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let stage = Stage()
    let menuBar = MenuBarController(stage: stage)
    print("Pip 窗口配置自检（不会显示窗口）")
    print(stage.debugSummary())
    print("菜单栏图标      = \(menuBar.isReady ? "创建成功（进程退出后消失）" : "创建失败")")
    exit(0)
}

// 声音自检：按当前音量依次放一遍所有声音，打印每个的长度/峰值，同时确认「自己出声不会被当成有音乐在放」
if cliArguments.contains("--voicetest") {
    Voice.shared.selfTest()
    exit(0)
}

// 正常 GUI 模式
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
