# Pip · Windows 版

**发给别人用**：发安装包 `Pip-Setup-<版本>.exe`，双击一路「下一步」。Win10 / Win11（64 位）自带 .NET Framework 4.8，不用另装东西。
- 装到当前用户的 `%LOCALAPPDATA%\Programs\Pip`，**不要管理员权限**；开始菜单 + 桌面图标，可选开机自启
- 卸载：「设置 → 应用」里找「Pip 桌面宠物」，或开始菜单里的「卸载 Pip 桌面宠物」；会删掉程序、开机自启和设置（`HKCU\Software\Pip`）
- 升级：直接装新版安装包，会先让正在跑的 Pip 退出再替换
- 第一次运行安装包如果弹出「Windows 已保护你的电脑」：点「更多信息」→「仍要运行」（没有买代码签名证书）

**自动更新**：Pip 启动 1 分钟后、之后每天看一次 GitHub Releases 最新版（托盘菜单「检查更新」也能手动查），比自己新就问要不要更新；
点「更新」→ 下载安装包、核对 SHA-256 → 静默安装 → 自动重新打开。点「否」= 这个版本自动检查时不再问。连不上 GitHub 只是更新不了，Pip 照常用。
**发新版**：`git tag v1.0.1 && git push origin v1.0.1`，CI 按标签版本号编译、自检、出安装包并发成 Release（见 `.github/workflows/windows.yml`）。

**不装也能用**：直接双击 `Pip.exe`（只有这一个文件）。开机自启记的是 exe 当时的位置，开了自启就别再挪它。

**做安装包**（Inno Setup 6，免费；`winget install JRSoftware.InnoSetup`）：先 `dotnet build windows/Pip.csproj -c Release`，再
`ISCC.exe windows\installer\Pip.iss` → `dist\Pip-Setup-1.0.0.exe`。版本号改 `Pip.iss` 顶上的 `AppVersion`。
GitHub CI 每次也会出一份（产物 `Pip-Setup-Windows-x64`）。

- 右下角托盘里有 Pip 的图标：右键 = 菜单（隐藏 / 暂停 / 爬窗口 / 跳舞 / 节日装扮 / 举牌提醒 / 提醒间隔 / 开机自动启动 / 退出）
- 在 Pip 身上点右键也是同一个菜单
- 再双击一次 Pip.exe = 把隐藏的小人叫出来
- 设置存在注册表 `HKCU\Software\Pip`；开机自启写在 `HKCU\...\Run\Pip`

**功能**：和 Mac 版同一套：站在任务栏上走来走去、拎起来扔（撞墙反弹、落地压扁）、站到窗口顶上（窗口挪了跟着走、关了掉下来）、
有声音就跳舞冒音符、5 分钟不碰电脑躺下睡觉冒 z、摸头眯眼脸红、定时举牌提醒、万圣节/圣诞/春节自动换装、全屏时自动藏起来。

**出问题时**：在 `Pip.exe` 所在文件夹的地址栏输入 `cmd` 回车，执行 `Pip.exe --selftest`。
跑完会自动打开结果文件夹（`%TEMP%\pip-selftest`），把里面的 `report.txt` 和几张 png 发过来就能定位。
（自检会动鼠标、开一个记事本窗口，十几秒后自己关掉。）

## 技术

- C# / .NET Framework 4.8 / WinForms 托盘；不引用任何第三方库
- 渲染：系统 OpenGL 3.3（显卡驱动自带），离屏帧缓冲 4×MSAA，低分屏也按 2 倍渲染再缩小；读回预乘 alpha 像素 → `UpdateLayeredWindow` 分层窗口
  （按像素 alpha 命中：透明的地方点不到，会穿透到下面的窗口）
- 模型、绒毛壳层着色器、灯光、状态机、动画全部逐行移植自 Mac 版（`Sources/Pip/*.swift`），颜色和 Mac 真机截图逐点对过
- 窗口顶边：`EnumWindows` + DWM 可见边框，扣掉被前面窗口挡住的部分；声音：默认扬声器上各程序音频会话的峰值电平
- 在 Mac 上：`dotnet build windows/Pip.csproj -c Release` 出 exe；`windows/tests/MacRender` 用同一份渲染代码在 Mac 上出图对比 + 跑状态机自检
- `.github/workflows/windows.yml`：在 GitHub 的 Windows 机器上编译 + 真机自检（用 Mesa 软件 OpenGL），需要先推到 GitHub

## 许可

代码 MIT（见仓库根目录 LICENSE）。声音素材（`Resources/sounds/`、`preview/sound-choices/`）全部 CC0，来源见各目录的 `来源.txt`。
