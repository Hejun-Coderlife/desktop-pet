// 舞台：一个跟着 Pip 走的 320×300 点透明小窗（分层窗口，按像素 alpha 命中——透明的地方点不到，会穿透到下面）。
// 逻辑逐段对应 Mac 版 Stage.swift
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Pip
{
    class PetForm : Form
    {
        public WinStage Stage;
        public PetForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Text = "Pip";
            TopMost = true;
        }
        protected override bool ShowWithoutActivation => true;
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.ExStyle |= Win32.WS_EX_LAYERED | Win32.WS_EX_TOOLWINDOW | Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOPMOST;
                return cp;
            }
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Win32.WM_MOUSEACTIVATE) { m.Result = (IntPtr)Win32.MA_NOACTIVATE; return; }
            base.WndProc(ref m);
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left) Stage?.PetMouseDown();
            else if (e.Button == MouseButtons.Right) Stage?.ShowMenuAtCursor();
        }
        protected override void OnMouseMove(MouseEventArgs e) { if ((e.Button & MouseButtons.Left) != 0) Stage?.PetMouseDragged(); }
        protected override void OnMouseUp(MouseEventArgs e) { if (e.Button == MouseButtons.Left) Stage?.PetMouseUp(); }
        protected override void OnPaintBackground(PaintEventArgs e) { }
        protected override void OnPaint(PaintEventArgs e) { }
    }

    class WinStage : IDisposable
    {
        public const float BoxW = 320, BoxH = 300;
        public readonly PetForm Form = new PetForm();
        public ContextMenuStrip Menu;

        readonly Renderer renderer = new Renderer();
        PetScene scene;
        Outfit outfit;
        public PetWorld World;
        WinEnv.ScreenInfo screen;
        readonly Timer timer = new Timer();
        readonly Stopwatch clock = Stopwatch.StartNew();
        double lastTick, lastEnv, lastTopmost;
        bool paused, userHidden, fullscreenHidden;
        float gazeX, gazeY;
        double lastMouseX, lastMouseY, mouseStillSince, downTime, downX, downY;
        double activeSeconds; int reminderIndex;
        static readonly string[] reminderTexts = { "喝口水吧 💧", "站起来走走 🚶", "看看远处 👀", "伸个懒腰 🙆" };
        double boxX = -1, boxY = -1;
        IntPtr memDC, dib, dibBits; int dibW, dibH;
        public string SoundApp;
        public int Frames;

        public double Now => clock.Elapsed.TotalSeconds;

        public WinStage()
        {
            renderer.Init();
            screen = WinEnv.Primary();
            World = new PetWorld(screen.WidthPts, screen.HeightPts, screen.GroundPts, 0x9E3779B9);
            outfit = Outfits.Current();
            scene = new PetScene(outfit);
            Form.Stage = this;
            Form.Cursor = Cursors.Hand;
            timer.Tick += (s, e) => Tick();
        }

        public string RendererInfo => renderer.Info;
        public bool IsPaused => paused;
        public bool IsUserHidden => userHidden;

        public void Start()
        {
            lastTick = Now;
            Form.Show();
            Layout(force: true);
            Present();
            SetInterval(1000 / 30);
            timer.Start();
        }

        void SetInterval(int ms) { if (timer.Interval != ms) timer.Interval = ms; }

        public void TogglePaused() { paused = !paused; if (!paused) lastTick = Now; }
        public void ToggleHidden()
        {
            userHidden = !userHidden;
            if (userHidden) Form.Hide(); else if (!fullscreenHidden) { Form.Show(); Layout(true); Present(); }
        }
        public void ShowIfHidden() { if (userHidden) ToggleHidden(); }

        public void RemindNow()
        {
            activeSeconds = 0;
            World.ShowSign(reminderTexts[reminderIndex++ % reminderTexts.Length]);
        }

        /// 节日装扮开关变了：立刻换一只（Mac 版要重开）
        public void RefreshOutfit()
        {
            var o = Outfits.Current();
            if (o == outfit) return;
            outfit = o; scene.Rebuild(o);
        }

        void Tick()
        {
            double now = Now;
            double dt = Math.Min(Math.Max(now - lastTick, 0), 0.12);
            lastTick = now;
            if (now - lastEnv > 0.5) { lastEnv = now; RefreshEnvironment(); }
            if (paused || userHidden || fullscreenHidden) { SetInterval(100); return; }
            FeedInputs(dt);
            UpdateMouse(dt);
            World.Update(dt);
            Present();
            SetInterval(World.IsMoving ? 1000 / 30 : 100);
            if (now - lastTopmost > 2)
            {
                lastTopmost = now;
                Win32.SetWindowPos(Form.Handle, Win32.HWND_TOPMOST, 0, 0, 0, 0, Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE);
            }
        }

        void FeedInputs(double dt)
        {
            double idle = WinEnv.IdleSeconds();
            World.IdleSeconds = idle;
            if (idle < 60) activeSeconds += dt;
            if (Settings.Reminders && activeSeconds >= Settings.ReminderMinutes * 60)
            {
                activeSeconds = 0;
                World.ShowSign(reminderTexts[reminderIndex++ % reminderTexts.Length]);
            }
        }

        void RefreshEnvironment()
        {
            var s = WinEnv.Primary();
            bool changed = s.Monitor.Left != screen.Monitor.Left || s.Monitor.Top != screen.Monitor.Top || s.Monitor.W != screen.Monitor.W
                           || s.Monitor.H != screen.Monitor.H || Math.Abs(s.Scale - screen.Scale) > 0.001 || s.Work.Bottom != screen.Work.Bottom;
            screen = s;
            if (changed) { World.SetGeometry(s.WidthPts, s.HeightPts, s.GroundPts); boxX = -1; }

            bool fs = WinEnv.IsFullscreen(s);
            if (fs != fullscreenHidden)
            {
                fullscreenHidden = fs;
                if (fs) Form.Hide(); else if (!userHidden) { Form.Show(); Layout(true); Present(); }
            }

            World.ClimbEnabled = Settings.ClimbWindows;
            if (Settings.ClimbWindows)
            {
                var all = WinEnv.TopEdges(s, World.GroundY, out var front);
                World.SetPlatform(front);
                World.SetPlatforms(all);
            }
            else { World.SetPlatform(null); World.SetPlatforms(new List<Platform>()); }

            SoundApp = Settings.Dance ? SoundOutput.Playing() : null;
            World.SoundPlaying = SoundApp != null;
        }

        // MARK: 鼠标（舞台坐标）

        void Cursor(out double x, out double y)
        {
            Win32.GetCursorPos(out var p);
            WinEnv.ToStage(screen, p.X, p.Y, out x, out y);
        }

        /// 小人的点击/摸头区域（舞台坐标）
        public (double x0, double y0, double x1, double y1) PetRect()
        {
            if (World.State == PetState.Sleep)
            {
                double x0 = World.Facing > 0 ? World.X - 34 : World.X - 96;
                return (x0, World.Y - 6, x0 + 130, World.Y + 60);
            }
            double w = World.HalfWidth * 2 + 10;
            return (World.X - w / 2, World.Y - 6, World.X + w / 2, World.Y + World.CharacterHeight);
        }
        bool InPet(double x, double y, double pad = 0) { var r = PetRect(); return x >= r.x0 - pad && x <= r.x1 + pad && y >= r.y0 - pad && y <= r.y1 + pad; }

        void UpdateMouse(double dt)
        {
            Cursor(out double px, out double py);
            bool leftDown = (Win32.GetAsyncKeyState(Win32.VK_LBUTTON) & 0x8000) != 0;
            if (World.State == PetState.Grabbed)
            {
                if (!leftDown) World.EndGrab();       // 松手事件丢了：兜底
                else World.Drag(px, py);
                UpdateLook(px, py);
                return;
            }
            bool inside = InPet(px, py);
            double moved = Math.Sqrt((px - lastMouseX) * (px - lastMouseX) + (py - lastMouseY) * (py - lastMouseY));
            double now = Now;
            if (moved > 1.5) mouseStillSince = now;
            if (inside && !leftDown && moved > 0.5 && moved < 60) World.Pet(moved / 260);
            lastMouseX = px; lastMouseY = py;

            bool nearFloor = py - World.SupportY < 160 && py > World.GroundY - 40;
            if (!inside && nearFloor && now - mouseStillSince > 1.5)
                World.AttentionX = Math.Min(Math.Max(px, World.HalfWidth), World.Width - World.HalfWidth);
            else if (moved > 1.5 || !nearFloor) World.AttentionX = null;
            UpdateLook(px, py);
        }

        void UpdateLook(double px, double py)
        {
            double dx = px - World.X, dy = py - (World.Y + 62);
            bool engaged = Math.Sqrt(dx * dx + dy * dy) < 320;
            float tx = engaged ? (float)Math.Max(-1, Math.Min(1, dx / 110)) : 0;
            float ty = engaged ? (float)Math.Max(-1, Math.Min(1, dy / 110)) : 0;
            gazeX += (tx - gazeX) * 0.22f; gazeY += (ty - gazeY) * 0.22f;
            Form.Cursor = World.State == PetState.Grabbed ? Cursors.SizeAll : Cursors.Hand;
        }

        public void PetMouseDown()
        {
            if (paused || userHidden || fullscreenHidden) return;
            Cursor(out double px, out double py);
            if (!InPet(px, py, 6)) return;
            downTime = Now; downX = px; downY = py;
            World.BeginGrab(px, py);
            Form.Cursor = Cursors.SizeAll;
        }

        public void PetMouseDragged()
        {
            if (World.State != PetState.Grabbed) return;
            Cursor(out double px, out double py);
            World.Drag(px, py);
        }

        public void PetMouseUp()
        {
            if (World.State != PetState.Grabbed) return;
            Cursor(out double px, out double py);
            if (Now - downTime < 0.25 && Math.Sqrt((px - downX) * (px - downX) + (py - downY) * (py - downY)) < 5) World.Click();
            else World.EndGrab();
            Form.Cursor = Cursors.Hand;
        }

        public void ShowMenuAtCursor()
        {
            if (Menu == null) return;
            Win32.GetCursorPos(out var p);
            Menu.Show(new Point(p.X, p.Y));
        }

        // MARK: 窗口位置 + 渲染

        void Layout(bool force = false)
        {
            double ox = World.X - BoxW / 2, oy = World.Y - 46;
            ox = Math.Min(Math.Max(ox, 0), Math.Max(0, World.Width - BoxW));
            oy = Math.Min(Math.Max(oy, 0), Math.Max(0, World.Height - BoxH));
            // 对齐到整像素，避免小框每帧亚像素抖动
            ox = Math.Round(ox * screen.Scale) / screen.Scale; oy = Math.Round(oy * screen.Scale) / screen.Scale;
            if (!force && ox == boxX && oy == boxY) return;
            boxX = ox; boxY = oy;
        }

        void EnsureDib(int w, int h)
        {
            if (w == dibW && h == dibH && dib != IntPtr.Zero) return;
            if (dib != IntPtr.Zero) Win32.DeleteObject(dib);
            if (memDC == IntPtr.Zero) memDC = Win32.CreateCompatibleDC(IntPtr.Zero);
            var bi = new Win32.BITMAPINFOHEADER { biSize = (uint)Marshal.SizeOf(typeof(Win32.BITMAPINFOHEADER)), biWidth = w, biHeight = h, biPlanes = 1, biBitCount = 32 };
            dib = Win32.CreateDIBSection(memDC, ref bi, 0, out dibBits, IntPtr.Zero, 0);   // 自下而上，和 glReadPixels 的行序一致
            Win32.SelectObject(memDC, dib);
            dibW = w; dibH = h;
        }

        void Present()
        {
            Layout();
            scene.Apply(World, Now, gazeX, gazeY);
            int w = (int)Math.Round(BoxW * screen.Scale), h = (int)Math.Round(BoxH * screen.Scale);
            EnsureDib(w, h);
            renderer.Render(scene.Roots, (float)boxX, (float)boxY, BoxW, BoxH, screen.Scale, dibBits);
            int left = screen.Monitor.Left + (int)Math.Round(boxX * screen.Scale);
            int top = screen.Monitor.Bottom - (int)Math.Round((boxY + BoxH) * screen.Scale);
            var dst = new Win32.POINT(left, top); var size = new Win32.SIZE(w, h); var src = new Win32.POINT(0, 0);
            var blend = new Win32.BLENDFUNCTION { BlendOp = Win32.AC_SRC_OVER, SourceConstantAlpha = 255, AlphaFormat = Win32.AC_SRC_ALPHA };
            var screenDC = Win32.GetDC(IntPtr.Zero);
            Win32.UpdateLayeredWindow(Form.Handle, screenDC, ref dst, ref size, memDC, ref src, 0, ref blend, Win32.ULW_ALPHA);
            Win32.ReleaseDC(IntPtr.Zero, screenDC);
            Frames++;
        }

        /// 自检：把当前画面存成 PNG
        public void Snapshot(string path)
        {
            if (dibBits == IntPtr.Zero) return;
            var buf = new byte[dibW * dibH * 4];
            Marshal.Copy(dibBits, buf, 0, buf.Length);
            Png.SaveRender(path, buf, dibW, dibH);
        }

        public string Describe()
        {
            var r = PetRect();
            return $"{screen}；地面 {World.GroundY:0.#} 点；状态 {World.State.Name()}；位置 ({World.X:0},{World.Y:0})；窗口顶边 {World.Platforms.Count} 个"
                   + (World.Standing.HasValue ? $"；站在 {World.Standing.Value}" : "") + $"；声音 {SoundApp ?? "无"}；已画 {Frames} 帧";
        }

        public void Dispose()
        {
            timer.Stop();
            if (dib != IntPtr.Zero) Win32.DeleteObject(dib);
            if (memDC != IntPtr.Zero) Win32.DeleteDC(memDC);
        }
    }
}
