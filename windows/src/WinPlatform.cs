// Windows 平台实现：OpenGL 上下文、文字贴图、注册表开关、屏幕/任务栏/窗口顶边、全屏检测、空闲时间、有没有声音
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace Pip
{
    /// 隐藏窗口上的 OpenGL 3.3 上下文（只做离屏渲染，画面通过分层窗口贴出去）
    static class WinGL
    {
        static System.Windows.Forms.Form host;
        static IntPtr hdc, ctx;
        public static string Error;

        static string Diag(int fmt)
        {
            int err = Marshal.GetLastWin32Error();
            var sb = new StringBuilder(260);
            Win32.GetModuleFileName(Win32.GetModuleHandle("opengl32.dll"), sb, 260);
            var d = new Win32.PIXELFORMATDESCRIPTOR();
            Win32.DescribePixelFormat(hdc, fmt, (uint)Marshal.SizeOf(typeof(Win32.PIXELFORMATDESCRIPTOR)), ref d);
            return $"（错误码 {err}，格式 #{fmt} flags=0x{d.dwFlags:X} 颜色{d.cColorBits}/透明{d.cAlphaBits}/深度{d.cDepthBits}，opengl32={sb}）";
        }

        public static bool Init()
        {
            try
            {
                // exe 旁边放了 opengl32.dll（如 CI 的 Mesa 软件渲染）就按完整路径先载入，
                // 免得 gdi32 的 ChoosePixelFormat 抢先从 System32 载入系统那份
                var local = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "opengl32.dll");
                if (System.IO.File.Exists(local)) Win32.LoadLibrary(local);
                host = new System.Windows.Forms.Form { ShowInTaskbar = false, FormBorderStyle = System.Windows.Forms.FormBorderStyle.None, Size = new Size(16, 16) };
                var h = host.Handle;   // 不 Show，只要句柄和 DC
                hdc = Win32.GetDC(h);
                var pfd = new Win32.PIXELFORMATDESCRIPTOR
                {
                    nSize = (ushort)Marshal.SizeOf(typeof(Win32.PIXELFORMATDESCRIPTOR)), nVersion = 1,
                    dwFlags = 0x4 | 0x20 | 0x1,   // DRAW_TO_WINDOW | SUPPORT_OPENGL | DOUBLEBUFFER
                    iPixelType = 0, cColorBits = 32, cAlphaBits = 8, cDepthBits = 24, iLayerType = 0
                };
                int fmt = Win32.ChoosePixelFormat(hdc, ref pfd);
                if (fmt == 0 || !Win32.SetPixelFormat(hdc, fmt, ref pfd)) { Error = "设置像素格式失败"; return false; }
                var legacy = Win32.wglCreateContext(hdc);
                if (legacy == IntPtr.Zero || !Win32.wglMakeCurrent(hdc, legacy)) { Error = "创建 OpenGL 上下文失败" + Diag(fmt); return false; }
                ctx = legacy;
                // 能拿到 3.3 core 就用 core（Mesa 等驱动的兼容模式版本很低）
                var p = Win32.wglGetProcAddress("wglCreateContextAttribsARB");
                if (p != IntPtr.Zero)
                {
                    var create = (Win32.WglCreateContextAttribsARB)Marshal.GetDelegateForFunctionPointer(p, typeof(Win32.WglCreateContextAttribsARB));
                    int[] attrs = { 0x2091, 3, 0x2092, 3, 0x9126, 0x1, 0 };   // MAJOR 3, MINOR 3, PROFILE core
                    var core = create(hdc, IntPtr.Zero, attrs);
                    if (core != IntPtr.Zero && Win32.wglMakeCurrent(hdc, core)) { Win32.wglDeleteContext(legacy); ctx = core; }
                    else Win32.wglMakeCurrent(hdc, legacy);
                }
                var gl32 = Win32.LoadLibrary("opengl32.dll");
                var missing = GL.Load(name =>
                {
                    var f = Win32.wglGetProcAddress(name);
                    long v = f.ToInt64();
                    if (v == 0 || v == 1 || v == 2 || v == 3 || v == -1) f = Win32.GetProcAddress(gl32, name);
                    return f;
                });
                if (missing != null) { Error = "显卡驱动不支持 OpenGL 3.3（缺少 " + missing + "）：" + GL.Str(GL.RENDERER) + " " + GL.Str(GL.VERSION); return false; }
                return true;
            }
            catch (Exception e) { Error = e.Message; return false; }
        }
    }

    /// 放 Pip 的声音：winmm 异步播内存里的 WAV（同一时间只一个声音，新的会顶掉旧的）
    static class WinVoice
    {
        [DllImport("winmm.dll", SetLastError = true)]
        static extern bool PlaySound(IntPtr wav, IntPtr hmod, uint flags);
        const uint SND_ASYNC = 0x1, SND_NODEFAULT = 0x2, SND_MEMORY = 0x4;
        // 异步播放期间这块内存不能动：用非托管内存（托管数组会被 GC 挪走），播下一个时再释放上一个
        static IntPtr playing = IntPtr.Zero;
        public static void Install() => Voice.Output = wav =>
        {
            var mem = Marshal.AllocHGlobal(wav.Length);
            Marshal.Copy(wav, 0, mem, wav.Length);
            PlaySound(mem, IntPtr.Zero, SND_ASYNC | SND_NODEFAULT | SND_MEMORY);   // 会先停掉正在放的
            if (playing != IntPtr.Zero) Marshal.FreeHGlobal(playing);
            playing = mem;
        };
    }

    /// GDI+ 文字贴图（微软雅黑粗体；音符用 Segoe UI Symbol，emoji 用 Segoe UI Emoji 兜底）
    class GdiText : ITextRasterizer
    {
        public Texture Text(string text, float fontSize, uint color, int w, int h, uint? background)
        {
            using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppPArgb))
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                Color C(uint v) => Color.FromArgb(255, (int)((v >> 16) & 0xFF), (int)((v >> 8) & 0xFF), (int)(v & 0xFF));
                if (background.HasValue)
                {
                    var r = new RectangleF(3, 3, w - 6, h - 6);
                    using (var path = Rounded(r, 18))
                    {
                        using (var b = new SolidBrush(C(background.Value))) g.FillPath(b, path);
                        using (var pen = new Pen(C(0xB89C7E), 4)) g.DrawPath(pen, path);
                    }
                }
                // 分段排版：emoji（代理对）用 Segoe UI Emoji，音符用 Segoe UI Symbol，其余微软雅黑粗体。
                // GraphicsPath.AddString 不会自动换字体，所以自己拆段、量宽、整体居中
                var runs = new List<(string text, string family)>();
                for (int i = 0; i < text.Length;)
                {
                    int len = char.IsSurrogatePair(text, i) ? 2 : 1;
                    string ch = text.Substring(i, len);
                    string fam = len == 2 || ch == "\u2600" ? "Segoe UI Emoji" : "♪♫♬".Contains(ch) ? "Segoe UI Symbol" : "Microsoft YaHei UI";
                    if (runs.Count > 0 && runs[runs.Count - 1].family == fam) runs[runs.Count - 1] = (runs[runs.Count - 1].text + ch, fam);
                    else runs.Add((ch, fam));
                    i += len;
                }
                var paths = new List<GraphicsPath>();
                float x = 0, top = float.MaxValue, bottom = float.MinValue;
                using (var sf = StringFormat.GenericTypographic)
                {
                    foreach (var run in runs)
                    {
                        var gp = new GraphicsPath();
                        FontFamily ff;
                        try { ff = new FontFamily(run.family); } catch { ff = FontFamily.GenericSansSerif; }
                        var style = ff.IsStyleAvailable(FontStyle.Bold) ? FontStyle.Bold : FontStyle.Regular;
                        gp.AddString(run.text, ff, (int)style, fontSize, new PointF(0, 0), sf);
                        var b = gp.GetBounds();
                        if (b.Width <= 0) { gp.Dispose(); x += fontSize * 0.3f; continue; }
                        using (var m = new Matrix()) { m.Translate(x - b.Left + (paths.Count > 0 ? fontSize * 0.12f : 0), 0); gp.Transform(m); }
                        var nb = gp.GetBounds();
                        x = nb.Right; top = Math.Min(top, nb.Top); bottom = Math.Max(bottom, nb.Bottom);
                        paths.Add(gp);
                    }
                }
                if (paths.Count > 0)
                {
                    float totalW = x, totalH = bottom - top;
                    using (var brush = new SolidBrush(C(color)))
                    using (var m = new Matrix())
                    {
                        m.Translate((w - totalW) / 2, (h - totalH) / 2 - top);
                        foreach (var gp in paths) { gp.Transform(m); g.FillPath(brush, gp); gp.Dispose(); }
                    }
                }
                var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                var px = new byte[w * h * 4];
                for (int y = 0; y < h; y++) Marshal.Copy(data.Scan0 + y * data.Stride, px, y * w * 4, w * 4);
                bmp.UnlockBits(data);
                for (int i = 0; i < px.Length; i += 4) { byte b = px[i]; px[i] = px[i + 2]; px[i + 2] = b; }   // BGRA → RGBA（都是预乘）
                return new Texture { W = w, H = h, Rgba = px };
            }
        }

        static GraphicsPath Rounded(RectangleF r, float rad)
        {
            var p = new GraphicsPath(); float d = rad * 2;
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
    }

    class RegistryStore : ISettingsStore
    {
        const string KeyPath = @"Software\Pip";
        public object Get(string key)
        {
            try { using (var k = Registry.CurrentUser.OpenSubKey(KeyPath)) return k?.GetValue(key); } catch { return null; }
        }
        public void Set(string key, object value)
        {
            try { using (var k = Registry.CurrentUser.CreateSubKey(KeyPath)) k.SetValue(key, value is bool b ? (b ? 1 : 0) : value, RegistryValueKind.DWord); } catch { }
        }

        const string RunPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public static bool AutoStart
        {
            get { try { using (var k = Registry.CurrentUser.OpenSubKey(RunPath)) return k?.GetValue("Pip") != null; } catch { return false; } }
            set
            {
                try
                {
                    using (var k = Registry.CurrentUser.CreateSubKey(RunPath))
                    {
                        if (value) k.SetValue("Pip", "\"" + System.Windows.Forms.Application.ExecutablePath + "\"");
                        else k.DeleteValue("Pip", false);
                    }
                }
                catch { }
            }
        }
    }

    /// 主屏 / 任务栏 / 窗口 / 空闲 / 全屏
    static class WinEnv
    {
        public struct ScreenInfo
        {
            public Win32.RECT Monitor, Work; public float Scale; public IntPtr Handle;
            public double WidthPts => Monitor.W / Scale;
            public double HeightPts => Monitor.H / Scale;
            /// 任务栏在底部时的高度（点）；任务栏在别的边或自动隐藏 = 0
            public double GroundPts => (Monitor.Bottom - Work.Bottom) / Scale;
            public override string ToString() => $"显示器 {Monitor}，工作区 {Work}，缩放 {Scale * 100:0}%";
        }

        public static ScreenInfo Primary()
        {
            var h = Win32.MonitorFromPoint(new Win32.POINT(0, 0), 1 /* PRIMARY */);
            var mi = new Win32.MONITORINFO { cbSize = Marshal.SizeOf(typeof(Win32.MONITORINFO)) };
            Win32.GetMonitorInfo(h, ref mi);
            float scale = 1;
            try { if (Win32.GetDpiForMonitor(h, 0, out uint dx, out _) == 0 && dx > 0) scale = dx / 96f; } catch { }
            return new ScreenInfo { Monitor = mi.rcMonitor, Work = mi.rcWork, Scale = scale, Handle = h };
        }

        /// 屏幕像素 → 舞台坐标（主屏左下为原点、y 向上，单位点）
        public static void ToStage(ScreenInfo s, int px, int py, out double x, out double y)
        {
            x = (px - s.Monitor.Left) / (double)s.Scale;
            y = (s.Monitor.Bottom - py) / (double)s.Scale;
        }

        public static double IdleSeconds()
        {
            var li = new Win32.LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf(typeof(Win32.LASTINPUTINFO)) };
            if (!Win32.GetLastInputInfo(ref li)) return 0;
            return unchecked(Win32.GetTickCount() - li.dwTime) / 1000.0;
        }

        static string ClassOf(IntPtr h) { var sb = new StringBuilder(256); Win32.GetClassName(h, sb, sb.Capacity); return sb.ToString(); }

        static readonly HashSet<string> shellClasses = new HashSet<string>
        {
            "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "NotifyIconOverflowWindow", "Windows.UI.Core.CoreWindow",
            "TopLevelWindowForOverflowXamlIsland", "XamlExplorerHostIslandWindow", "SysShadow", "tooltips_class32", "#32768"
        };

        static bool Bounds(IntPtr h, out Win32.RECT r)
        {
            // DWM 的「可见边框」：不含 Win10/11 那圈看不见的拉伸边
            if (Win32.DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(Win32.RECT))) == 0) return true;
            return Win32.GetWindowRect(h, out r);
        }

        static bool Cloaked(IntPtr h) => Win32.DwmGetWindowAttribute(h, 14, out int c, 4) == 0 && c != 0;

        /// 最前面的窗口铺满了主屏（全屏视频、游戏、PPT 放映）
        public static bool IsFullscreen(ScreenInfo s)
        {
            try
            {
                if (Win32.SHQueryUserNotificationState(out int st) == 0 && (st == 2 || st == 3 || st == 4)) return true;
            }
            catch { }
            var fg = Win32.GetForegroundWindow();
            if (fg == IntPtr.Zero || fg == Win32.GetShellWindow() || fg == Win32.GetDesktopWindow()) return false;
            if (shellClasses.Contains(ClassOf(fg))) return false;
            Win32.GetWindowThreadProcessId(fg, out uint pid);
            if (pid == (uint)Process.GetCurrentProcess().Id) return false;
            if (!Bounds(fg, out var r)) return false;
            return r.Left <= s.Monitor.Left && r.Top <= s.Monitor.Top && r.Right >= s.Monitor.Right && r.Bottom >= s.Monitor.Bottom;
        }

        /// 所有普通窗口露在外面的顶边（被更前面的窗口盖住的那段扣掉，取剩下最长的一段）——和 Mac 版 allTopEdges 同一套规则
        public static List<Platform> TopEdges(ScreenInfo s, double groundY, out Platform? front)
        {
            var result = new List<Platform>();
            var inFront = new List<Win32.RECT>();
            uint me = (uint)Process.GetCurrentProcess().Id;
            Platform? firstApp = null;
            bool sawFirst = false;
            Win32.EnumWindows((h, _) =>
            {
                if (!Win32.IsWindowVisible(h) || Win32.IsIconic(h) || Cloaked(h)) return true;
                int ex = Win32.GetWindowLong(h, Win32.GWL_EXSTYLE);
                if ((ex & Win32.WS_EX_TRANSPARENT) != 0) return true;                     // 点不着的覆盖层（录屏边框、游戏叠加层）
                if ((ex & Win32.WS_EX_TOOLWINDOW) != 0 && (ex & Win32.WS_EX_APPWINDOW) == 0) return true;
                if (shellClasses.Contains(ClassOf(h))) return true;
                Win32.GetWindowThreadProcessId(h, out uint pid);
                if (pid == me) return true;
                if (!Bounds(h, out var r) || r.W <= 0 || r.H <= 0) return true;
                bool coversScreen = r.Left <= s.Monitor.Left && r.Top <= s.Monitor.Top && r.Right >= s.Monitor.Right && r.Bottom >= s.Monitor.Bottom;
                // 盖满整屏的窗口（多半是看不见的覆盖层；真全屏时 Pip 本来就藏起来了）不当平台，也不算挡住别人
                if (coversScreen) return true;
                try
                {
                    double wPts = r.W / s.Scale, hPts = r.H / s.Scale;
                    if (wPts < 100 || hPts < 60) return true;
                    double top = (s.Monitor.Bottom - r.Top) / (double)s.Scale;
                    double x0 = (r.Left - s.Monitor.Left) / (double)s.Scale, x1 = (r.Right - s.Monitor.Left) / (double)s.Scale;
                    if (!sawFirst)
                    {
                        sawFirst = true;
                        if (top > groundY + 70 && top < s.HeightPts - 30 - 92)
                            firstApp = new Platform(h.ToInt64(), Math.Max(0, x0), Math.Min(s.WidthPts, x1), top);
                    }
                    if (!(top > groundY + 50 && top < s.HeightPts - 30 - 60)) return true;
                    if (r.Right <= s.Monitor.Left || r.Left >= s.Monitor.Right) return true;   // 不在主屏上
                    var segs = new List<(int a, int b)> { (r.Left, r.Right) };
                    foreach (var f in inFront)
                    {
                        if (!(f.Top < r.Top + 1 && f.Bottom > r.Top - 1)) continue;
                        var next = new List<(int, int)>();
                        foreach (var sg in segs)
                        {
                            if (f.Right <= sg.a || f.Left >= sg.b) { next.Add(sg); continue; }
                            if (f.Left > sg.a) next.Add((sg.a, f.Left));
                            if (f.Right < sg.b) next.Add((f.Right, sg.b));
                        }
                        segs = next;
                    }
                    (int a, int b) best = (0, 0);
                    foreach (var sg in segs) if (sg.b - sg.a > best.b - best.a) best = sg;
                    double bx0 = Math.Max(0, (best.a - s.Monitor.Left) / (double)s.Scale), bx1 = Math.Min(s.WidthPts, (best.b - s.Monitor.Left) / (double)s.Scale);
                    if (bx1 - bx0 >= 70) result.Add(new Platform(h.ToInt64(), bx0, bx1, top));
                }
                finally { inFront.Add(r); }
                return true;
            }, IntPtr.Zero);
            front = firstApp;
            return result;
        }

        /// 调试：列出主屏上可见的顶层窗口
        public static List<string> DescribeWindows()
        {
            var list = new List<string>();
            Win32.EnumWindows((h, _) =>
            {
                if (!Win32.IsWindowVisible(h) || Win32.IsIconic(h)) return true;
                var sb = new StringBuilder(200); Win32.GetWindowText(h, sb, sb.Capacity);
                Bounds(h, out var r);
                int ex = Win32.GetWindowLong(h, Win32.GWL_EXSTYLE);
                list.Add($"{ClassOf(h)} \"{sb}\" {r} ex=0x{ex:X} cloaked={Cloaked(h)}");
                return list.Count < 40;
            }, IntPtr.Zero);
            return list;
        }
    }

    /// 有没有程序在出声：遍历默认扬声器上的音频会话，看峰值电平（不录音、听不到内容，免权限）
    static class SoundOutput
    {
        static readonly HashSet<string> ignored = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Zoom", "Teams", "ms-teams", "wemeetapp", "WeMeet", "TencentMeeting", "Skype", "Pip", "blender", "Resolve"
        };

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator
        {
            int EnumAudioEndpoints(int dataFlow, int mask, out IntPtr devices);
            int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice
        {
            int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        }

        [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionManager2
        {
            int GetAudioSessionControl(IntPtr guid, int flags, out IntPtr ctl);
            int GetSimpleAudioVolume(IntPtr guid, int flags, out IntPtr vol);
            int GetSessionEnumerator(out IAudioSessionEnumerator e);
        }

        [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionEnumerator
        {
            int GetCount(out int count);
            int GetSession(int index, [MarshalAs(UnmanagedType.IUnknown)] out object session);
        }

        [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionControl2
        {
            int GetState(out int state);
            int GetDisplayName(out IntPtr name);
            int SetDisplayName(string name, ref Guid ctx);
            int GetIconPath(out IntPtr path);
            int SetIconPath(string path, ref Guid ctx);
            int GetGroupingParam(out Guid g);
            int SetGroupingParam(ref Guid g, ref Guid ctx);
            int RegisterAudioSessionNotification(IntPtr n);
            int UnregisterAudioSessionNotification(IntPtr n);
            int GetSessionIdentifier(out IntPtr id);
            int GetSessionInstanceIdentifier(out IntPtr id);
            int GetProcessId(out uint pid);
            int IsSystemSoundsSession();
            int SetDuckingPreference(bool optOut);
        }

        [ComImport, Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioMeterInformation
        {
            int GetPeakValue(out float peak);
        }

        public static string LastError;

        /// 返回正在出声的程序名（没有就 null）
        public static string Playing()
        {
            object enumObj = null, mgrObj = null, sessEnum = null;
            IMMDevice dev = null;
            try
            {
                var en = (IMMDeviceEnumerator)(enumObj = new MMDeviceEnumerator());
                if (en.GetDefaultAudioEndpoint(0 /* eRender */, 1 /* eMultimedia */, out dev) != 0 || dev == null) return null;
                var iid = typeof(IAudioSessionManager2).GUID;
                if (dev.Activate(ref iid, 0x17 /* CLSCTX_ALL */, IntPtr.Zero, out mgrObj) != 0) return null;
                var mgr = (IAudioSessionManager2)mgrObj;
                if (mgr.GetSessionEnumerator(out var se) != 0) return null;
                sessEnum = se;
                se.GetCount(out int n);
                uint me = (uint)Process.GetCurrentProcess().Id;
                for (int i = 0; i < n; i++)
                {
                    object s = null;
                    try
                    {
                        if (se.GetSession(i, out s) != 0 || s == null) continue;
                        var ctl = s as IAudioSessionControl2;
                        if (ctl == null) continue;
                        if (ctl.IsSystemSoundsSession() == 0) continue;          // S_OK = 是系统提示音
                        ctl.GetProcessId(out uint pid);
                        if (pid == 0 || pid == me) continue;
                        ctl.GetState(out int state);
                        if (state != 1) continue;                                // AudioSessionStateActive
                        var meter = s as IAudioMeterInformation;
                        if (meter == null || meter.GetPeakValue(out float peak) != 0 || peak < 0.0005f) continue;
                        string name;
                        try { name = Process.GetProcessById((int)pid).ProcessName; } catch { continue; }
                        if (ignored.Contains(name)) continue;
                        return name;
                    }
                    finally { if (s != null) Marshal.ReleaseComObject(s); }
                }
                return null;
            }
            catch (Exception e) { LastError = e.Message; return null; }
            finally
            {
                foreach (var o in new object[] { sessEnum, mgrObj, dev, enumObj }) if (o != null) try { Marshal.ReleaseComObject(o); } catch { }
            }
        }
    }
}
