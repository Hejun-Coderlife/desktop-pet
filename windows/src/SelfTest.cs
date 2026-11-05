// Windows 自检：Pip.exe --selftest 输出目录
// 1 状态机  2 离屏渲染各状态（PNG）  3 环境（屏幕、任务栏、窗口顶边、全屏、空闲、声音）
// 4 真窗口：开分层窗口跑起来 → 截屏确认看得见 → 模拟鼠标拎起来扔 → 开个记事本当平台、扔上去看能不能站住
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace Pip
{
    static class SelfTest
    {
        static StringBuilder log = new StringBuilder();
        static List<string> problems = new List<string>();
        static string dir;

        static void Line(string s) { log.AppendLine(s); Console.WriteLine(s); }
        static void Fail(string s) { problems.Add(s); Line("  ✗ " + s); }

        public static int Run(string outDir)
        {
            dir = outDir; Directory.CreateDirectory(dir);
            try { Body(); }
            catch (Exception e) { Fail("异常：" + e); }
            Line(problems.Count == 0 ? "\nPASS" : $"\nFAIL（{problems.Count} 项）");
            File.WriteAllText(Path.Combine(dir, "report.txt"), log.ToString(), Encoding.UTF8);
            // 用户自己双击跑的（不是 CI）：跑完打开结果文件夹，方便把 report.txt 和截图发过来
            if (Environment.GetEnvironmentVariable("GITHUB_ACTIONS") == null)
                try { Process.Start("explorer.exe", "\"" + dir + "\""); } catch { }
            return problems.Count == 0 ? 0 : 1;
        }

        static void Body()
        {
            Line($"Pip 自检 {DateTime.Now:yyyy-MM-dd HH:mm:ss}，{Environment.OSVersion}，64 位进程={Environment.Is64BitProcess}");

            Line("\n[1] 状态机");
            var wl = new StringBuilder();
            if (!WorldTests.Run(wl)) Fail("状态机自检没过");
            Line(wl.ToString().TrimEnd());

            Line("\n[2] OpenGL 与离屏渲染");
            if (!WinGL.Init()) { Fail("OpenGL 初始化失败：" + WinGL.Error); return; }
            var r = new Renderer(); r.Init();
            Line("  " + r.Info);
            RenderCases(r);

            Line("\n[3] 环境");
            var s = WinEnv.Primary();
            Line("  " + s + $"，地面（任务栏上沿）{s.GroundPts:0.#} 点");
            Line($"  空闲 {WinEnv.IdleSeconds():0.0} 秒；全屏={WinEnv.IsFullscreen(s)}；在出声的程序={SoundOutput.Playing() ?? "无"}" + (SoundOutput.LastError != null ? $"（{SoundOutput.LastError}）" : ""));
            foreach (var w in WinEnv.DescribeWindows()) Line("    窗口 " + w);
            var edges = WinEnv.TopEdges(s, s.GroundPts, out var front);
            Line($"  可站的顶边 {edges.Count} 个：" + string.Join("；", edges));
            Line($"  最前面的窗口顶边：{(front.HasValue ? front.Value.ToString() : "无")}");
            Line($"  节日装扮：{Outfits.Current()}");

            Line("\n[4] 真窗口");
            LiveTest(s);

            Line("\n[5] 声音");
            foreach (Cue c in Enum.GetValues(typeof(Cue)))
            {
                var x = Voice.Samples(c);
                float peak = 0; foreach (var v in x) peak = Math.Max(peak, Math.Abs(v));
                Line($"  {c}：{x.Length / 44100.0:0.00} 秒，峰值 {peak:0.00}" + (peak > 0.99f ? "（削波）" : ""));
                if (peak > 0.99f || peak < 0.05f) Fail($"声音 {c} 音量不对（峰值 {peak:0.00}）");
            }
            var wav = Voice.Wav(Voice.Samples(Cue.Sign), 0.4f);
            File.WriteAllBytes(Path.Combine(dir, "voice-sign.wav"), wav);
            try { WinVoice.Install(); Voice.Play(Cue.Hop, true); Line("  [通过] 播放没报错（CI 机器没声卡，听不到是正常的）"); }
            catch (Exception e) { Fail("播放声音出错：" + e.Message); }
        }

        static void RenderCases(Renderer r)
        {
            var cases = new (string name, PetState st, double t, double phase, string sign, Outfit o)[]
            {
                ("idle", PetState.Idle, 0.3, 0, null, Outfit.None), ("walk", PetState.Walk, 1, 1.2, null, Outfit.None),
                ("grabbed", PetState.Grabbed, 0.4, 0, null, Outfit.None), ("sleep", PetState.Sleep, 2, 0, null, Outfit.None),
                ("dance", PetState.Dance, 0.6, 0, null, Outfit.None), ("petted", PetState.Petted, 0.3, 0, null, Outfit.None),
                ("sign", PetState.Sign, 0.3, 0, "喝口水吧 💧", Outfit.None), ("perch", PetState.Perch, 0.5, 0, null, Outfit.None),
                ("halloween", PetState.Idle, 0.3, 0, null, Outfit.Halloween), ("christmas", PetState.Idle, 0.3, 0, null, Outfit.Christmas),
                ("newyear", PetState.Idle, 0.3, 0, null, Outfit.NewYear),
            };
            float W = 160, H = 170, scale = 2;
            int pw = (int)(W * scale), ph = (int)(H * scale);
            var sheet = new byte[pw * cases.Length * ph * 4];
            for (int c = 0; c < cases.Length; c++)
            {
                var k = cases[c];
                var scene = new PetScene(k.o);
                var w = new PetWorld(W, H, 20);
                w.Preview(k.st, k.t, W / 2, 20, k.phase, 0, 0, 0, k.sign);
                scene.Apply(w, k.t, 0, 0);
                var buf = new byte[pw * ph * 4];
                var hnd = GCHandle.Alloc(buf, GCHandleType.Pinned);
                var sw = Stopwatch.StartNew();
                r.Render(scene.Roots, 0, 0, W, H, scale, hnd.AddrOfPinnedObject());
                hnd.Free();
                int opaque = 0; for (int i = 3; i < buf.Length; i += 4) if (buf[i] > 200) opaque++;
                Line($"  {k.name}: {sw.ElapsedMilliseconds} ms，不透明像素 {opaque}，GL 错误 0x{GL.GetError():X}");
                if (opaque < 3000) Fail($"{k.name} 渲染出来几乎是空的（{opaque} 像素）");
                Png.SaveRender(Path.Combine(dir, "render-" + k.name + ".png"), buf, pw, ph);
                // 拼一张总览（横排）
                for (int y = 0; y < ph; y++) Buffer.BlockCopy(buf, y * pw * 4, sheet, (y * pw * cases.Length + c * pw) * 4, pw * 4);
            }
            Png.SaveRender(Path.Combine(dir, "renders.png"), sheet, pw * cases.Length, ph);
            // 帧耗时：连续画 60 帧
            var sc = new PetScene(Outfit.None); var ww = new PetWorld(1600, 900, 40);
            var fb = new byte[(int)(320 * 2 * 300 * 2 * 4)]; var h2 = GCHandle.Alloc(fb, GCHandleType.Pinned);
            var t0 = Stopwatch.StartNew();
            for (int i = 0; i < 60; i++) { ww.Update(1 / 30.0); sc.Apply(ww, i / 30.0, 0, 0); r.Render(sc.Roots, (float)ww.X - 160, 0, 320, 300, 2, h2.AddrOfPinnedObject()); }
            h2.Free();
            Line($"  连续 60 帧（640×600 像素）平均 {t0.ElapsedMilliseconds / 60.0:0.0} ms/帧");
        }

        // MARK: 真窗口

        [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
        [DllImport("user32.dll")] static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
        [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr dst, int x, int y, int w, int h, IntPtr src, int sx, int sy, uint rop);
        const uint MOUSEEVENTF_LEFTDOWN = 2, MOUSEEVENTF_LEFTUP = 4;

        static Bitmap Capture(Rectangle rc)
        {
            // 直接 BitBlt：.NET Framework 的 CopyFromScreen 不接受 SourceCopy|CaptureBlt 组合值；CAPTUREBLT 才截得到分层窗口
            var bmp = new Bitmap(rc.Width, rc.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                var dst = g.GetHdc(); var scr = Win32.GetDC(IntPtr.Zero);
                BitBlt(dst, 0, 0, rc.Width, rc.Height, scr, rc.Left, rc.Top, 0x00CC0020 | 0x40000000);
                Win32.ReleaseDC(IntPtr.Zero, scr); g.ReleaseHdc(dst);
            }
            return bmp;
        }

        static void LiveTest(WinEnv.ScreenInfo s)
        {
            WinStage stage;
            try { stage = new WinStage(); } catch (Exception e) { Fail("建舞台失败：" + e.Message); return; }
            stage.Start();
            var steps = new List<(double at, Action act)>();
            Process notepad = null;
            var sw = new Stopwatch();
            // 某一步可以要求「等到条件成立（最多 N 秒）再往下走」，等的时间会自动算进后面步骤的顺延
            Func<bool> waitFor = null; double waitDeadline = 0;
            Win32.POINT PetScreen(double ox, double oy)
            {
                return new Win32.POINT(s.Monitor.Left + (int)((stage.World.X + ox) * s.Scale), s.Monitor.Bottom - (int)((stage.World.Y + oy) * s.Scale));
            }
            void Shot(string name)
            {
                using (var b = Capture(new Rectangle(s.Monitor.Left, s.Monitor.Top, s.Monitor.W, s.Monitor.H))) b.Save(Path.Combine(dir, name), ImageFormat.Png);
                stage.Snapshot(Path.Combine(dir, name.Replace(".png", "-window.png")));
            }
            bool sawFalling = false, sawStanding = false;
            var dragTo = new Win32.POINT(0, 0);
            steps.Add((2.0, () =>
            {
                Line("  2 秒：" + stage.Describe());
                Shot("live-1-start.png");
                // 截屏里 Pip 附近应该有亮色的绒毛像素（分层窗口真的显示出来了）
                var p = PetScreen(0, 45);
                using (var b = Capture(new Rectangle(p.X - 40, p.Y - 40, 80, 80)))
                {
                    int bright = 0;
                    for (int y = 0; y < b.Height; y++) for (int x = 0; x < b.Width; x++) { var c = b.GetPixel(x, y); if (c.R > 215 && c.G > 200 && c.B > 190 && Math.Abs(c.R - c.B) < 45) bright++; }
                    Line($"  截屏里 Pip 身上的浅色像素 {bright}/6400");
                    if (bright < 800) Fail("截屏里看不到 Pip（分层窗口没显示出来？）");
                }
            }));
            steps.Add((2.5, () =>
            {
                // 模拟鼠标：按住肚子往上拖 250 点，松手
                var p = PetScreen(0, 40);
                SetCursorPos(p.X, p.Y);
            }));
            steps.Add((2.7, () => { mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero); }));
            for (int i = 1; i <= 10; i++)
            {
                int k = i;
                steps.Add((2.7 + k * 0.03, () =>
                {
                    Win32.GetCursorPos(out var c);
                    SetCursorPos(c.X + (int)(12 * s.Scale), c.Y - (int)(25 * s.Scale));
                    if (k == 5) Line($"  拖动中：{stage.World.State.Name()} ({stage.World.X:0},{stage.World.Y:0})");
                }));
            }
            steps.Add((3.05, () =>
            {
                if (stage.World.State != PetState.Grabbed) Fail($"按住拖动时没被拎起来（状态 {stage.World.State.Name()}）");
                else Line("  [通过] 鼠标按住能拎起来");
                Shot("live-2-grabbed.png");
                mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
            }));
            steps.Add((3.15, () => { sawFalling = stage.World.State == PetState.Falling; Line($"  松手后：{stage.World.State.Name()} 速度 ({stage.World.VX:0},{stage.World.VY:0})"); if (!sawFalling) Fail("松手后没有掉下来"); }));
            steps.Add((4.6, () =>
            {
                Line("  落地后：" + stage.Describe());
                if (Math.Abs(stage.World.Y - stage.World.GroundY) > 1 && !stage.World.OnPlatform) Fail("扔出去以后没落回地面");
                SetCursorPos(s.Monitor.Left + 10, s.Monitor.Top + 10);
                try
                {
                    notepad = Process.Start("notepad.exe");
                    notepad.WaitForInputIdle(4000);
                }
                catch (Exception e) { Line("  开不了记事本：" + e.Message); }
            }));
            steps.Add((6.0, () =>
            {
                IntPtr h = IntPtr.Zero;
                try { notepad?.Refresh(); h = notepad?.MainWindowHandle ?? IntPtr.Zero; } catch { }
                if (h == IntPtr.Zero) { var hs = FindTopWindow("Notepad"); h = hs; }
                if (h == IntPtr.Zero) { Line("  没找到记事本窗口，跳过站窗口测试"); return; }
                int wx = s.Monitor.Left + (int)(500 * s.Scale), wy = s.Monitor.Bottom - (int)(520 * s.Scale);
                Win32.SetWindowPos(h, IntPtr.Zero, wx, wy, (int)(520 * s.Scale), (int)(300 * s.Scale), 0x40);
                Line($"  记事本放到 ({wx},{wy})");
            }));
            steps.Add((7.0, () =>
            {
                var plats = stage.World.Platforms;
                Line($"  看到的窗口顶边：{string.Join("；", plats)}");
                Platform? target = null;
                foreach (var p in plats) if (Math.Abs(p.Y - 520) < 30 && p.X1 - p.X0 > 200) target = p;
                if (!target.HasValue) { Fail("没认出记事本窗口的顶边"); return; }
                Line("  [通过] 认出了记事本的顶边 " + target.Value);
                // 用真鼠标：按住肚子 → 分几步拖到记事本正上方 → 慢慢松手
                var t = target.Value;
                var from = PetScreen(0, 40);
                dragTo = new Win32.POINT(s.Monitor.Left + (int)((t.X0 + t.X1) / 2 * s.Scale), s.Monitor.Bottom - (int)((t.Y + 110) * s.Scale));
                SetCursorPos(from.X, from.Y);
            }));
            steps.Add((7.1, () => { if (dragTo.X != 0) mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero); }));
            for (int i = 1; i <= 6; i++)
            {
                int k = i;
                steps.Add((7.1 + k * 0.05, () =>
                {
                    if (dragTo.X == 0) return;
                    Win32.GetCursorPos(out var c);
                    int n = 7 - k;   // 剩下几步，每步走剩余距离的 1/n
                    SetCursorPos(c.X + (dragTo.X - c.X) / n, c.Y + (dragTo.Y - c.Y) / n);
                }));
            }
            steps.Add((7.5, () => { if (stage.World.State != PetState.Grabbed) Line($"  拖到记事本上方时状态：{stage.World.State.Name()}"); }));
            steps.Add((7.6, () => { if (dragTo.X != 0) mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero); }));
            // 没显卡时动作是慢放的：等它不再往下掉（最多 20 秒）再检查有没有站住
            steps.Add((7.8, () => { waitFor = () => stage.World.State != PetState.Falling && stage.World.State != PetState.Grabbed; waitDeadline = sw.Elapsed.TotalSeconds + 20; }));
            steps.Add((9.0, () =>
            {
                sawStanding = stage.World.OnPlatform;
                Line("  扔到记事本上方以后：" + stage.Describe());
                if (!sawStanding) Fail("扔到窗口上方没站住");
                else Line("  [通过] 站在了记事本窗口顶上");
                Shot("live-3-on-window.png");
            }));
            steps.Add((9.5, () =>
            {
                // 把记事本挪走 → 应该跟着走或掉下来；关掉 → 一定掉下来
                try { notepad?.Kill(); } catch { }
            }));
            steps.Add((11.0, () =>
            {
                Line("  关掉记事本以后：" + stage.Describe());
                if (stage.World.OnPlatform) Fail("窗口关了还站在空中");
                stage.RemindNow();
            }));
            steps.Add((12.0, () => { Shot("live-4-sign.png"); Line("  举牌：" + stage.Describe()); if (stage.World.State != PetState.Sign) Fail("现在提醒一下 没举牌"); }));
            steps.Add((12.5, () => Application.ExitThread()));

            // 每画一帧最多走一步：没显卡时一帧要大半秒，不这样的话鼠标按下/拖动/松手会挤在两帧之间，Pip 来不及反应。
            // 步骤的时间点按"已经走过的时间"往后顺延，相邻步骤之间至少隔着一帧
            sw.Restart();
            int next = 0, frameAtStep = -1;
            double lag = 0;
            // 某一步可以要求「等到条件成立（最多 N 秒）再往下走」，等的时间算进 lag
            var drive = new Timer { Interval = 10 };
            drive.Tick += (o, e) =>
            {
                if (next >= steps.Count || stage.Frames <= frameAtStep) return;
                if (waitFor != null)
                {
                    if (!waitFor() && sw.Elapsed.TotalSeconds < waitDeadline) return;
                    waitFor = null;
                }
                double at = steps[next].at + lag;
                if (sw.Elapsed.TotalSeconds < at) return;
                lag = Math.Max(lag, sw.Elapsed.TotalSeconds - steps[next].at);
                var a = steps[next++].act; frameAtStep = stage.Frames;
                try { a(); } catch (Exception ex) { Fail("步骤异常：" + ex.Message); }
            };
            drive.Start();
            Application.Run();
            drive.Stop();
            Line($"  共画了 {stage.Frames} 帧，用时 {sw.Elapsed.TotalSeconds:0.0} 秒");
            double fps = stage.Frames / sw.Elapsed.TotalSeconds;
            Line($"  平均 {fps:0.0} 帧/秒（{(stage.Software ? "软件渲染" : "显卡")}）");
            if (!stage.Software && fps < 8) Fail($"帧数太少（{fps:0.0} 帧/秒）");
            stage.Dispose();
            try { notepad?.Kill(); } catch { }
        }

        static IntPtr FindTopWindow(string cls)
        {
            IntPtr found = IntPtr.Zero;
            Win32.EnumWindows((h, _) =>
            {
                var sb = new StringBuilder(64); Win32.GetClassName(h, sb, 64);
                if (sb.ToString() == cls && Win32.IsWindowVisible(h)) { found = h; return false; }
                return true;
            }, IntPtr.Zero);
            return found;
        }
    }
}
