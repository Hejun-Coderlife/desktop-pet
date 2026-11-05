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

// 正常 GUI 模式
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
