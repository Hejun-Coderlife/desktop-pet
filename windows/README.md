# Pip · Windows 版

**用法**：双击 `Pip.exe`。Win10 / Win11 自带 .NET Framework 4.8，不用装任何东西；只有这一个文件。
第一次打开如果弹出「Windows 已保护你的电脑」：点「更多信息」→「仍要运行」（没有买代码签名证书）。

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
