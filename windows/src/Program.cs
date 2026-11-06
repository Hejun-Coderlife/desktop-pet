// 入口：单实例、托盘菜单（= Mac 版菜单栏图标）、自检模式
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Pip
{
    static class Program
    {
        static WinStage stage;
        static NotifyIcon tray;
        const string MutexName = "Local\\PipDesktopPet.Single";
        const string ShowEventName = "Local\\PipDesktopPet.Show";

        [STAThread]
        static int Main(string[] args)
        {
            try { Win32.SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch { try { Win32.SetProcessDPIAware(); } catch { } }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Settings.Store = new RegistryStore();
            WinVoice.Install();
            Tex.TextRasterizer = new GdiText();

            int si = Array.IndexOf(args, "--selftest");
            if (si >= 0) return SelfTest.Run(si + 1 < args.Length ? args[si + 1] : Path.Combine(Path.GetTempPath(), "pip-selftest"));
            if (Array.IndexOf(args, "--quit") >= 0) { Signal("quit"); return 0; }

            // 已经在运行：叫它把小人显示出来，自己退出（相当于 Mac 版再双击一次 Pip.app）
            var mutex = new Mutex(true, MutexName, out bool first);
            if (!first) { Signal("show"); return 0; }

            if (!WinGL.Init())
            {
                MessageBox.Show("Pip 需要显卡支持 OpenGL 3.3，这台电脑上没能启动：\n\n" + WinGL.Error +
                                "\n\n可以试试更新显卡驱动。远程桌面里通常也用不了。", "Pip", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return 2;
            }
            try { stage = new WinStage(); }
            catch (Exception e)
            {
                MessageBox.Show("Pip 启动失败：\n\n" + e.Message, "Pip", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 3;
            }
            BuildTray();
            Updater.Start();
            stage.Start();
            ListenForSignals();
            Application.Run();
            tray.Visible = false;
            stage.Dispose();
            GC.KeepAlive(mutex);
            return 0;
        }

        // MARK: 进程间：再次启动 = 显示；--quit = 退出

        static void Signal(string what)
        {
            try
            {
                using (var ev = EventWaitHandle.OpenExisting(what == "quit" ? ShowEventName + ".quit" : ShowEventName)) ev.Set();
            }
            catch { }
        }

        static void ListenForSignals()
        {
            var show = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
            var quit = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName + ".quit");
            var ctx = SynchronizationContext.Current;
            var t = new Thread(() =>
            {
                var hs = new WaitHandle[] { show, quit };
                while (true)
                {
                    int i = WaitHandle.WaitAny(hs);
                    if (i == 0) ctx.Post(_ => stage.ShowIfHidden(), null);
                    else { ctx.Post(_ => Application.Exit(), null); return; }
                }
            }) { IsBackground = true };
            t.Start();
        }

        // MARK: 托盘（右下角），右键小人也弹同一个菜单

        static void BuildTray()
        {
            var menu = new ContextMenuStrip { ShowImageMargin = false, ShowCheckMargin = true };
            var hide = new ToolStripMenuItem("隐藏小人");
            hide.Click += (s, e) => stage.ToggleHidden();
            var pause = new ToolStripMenuItem("暂停（停在原地不动）");
            pause.Click += (s, e) => stage.TogglePaused();
            menu.Items.Add(hide); menu.Items.Add(pause);
            menu.Items.Add(new ToolStripSeparator());

            var toggles = new List<(ToolStripMenuItem item, Func<bool> get, Action<bool> set)>();
            void Toggle(string title, Func<bool> get, Action<bool> set)
            {
                var it = new ToolStripMenuItem(title);
                it.Click += (s, e) => { set(!get()); };
                toggles.Add((it, get, set));
                menu.Items.Add(it);
            }
            Toggle("爬到窗口上", () => Settings.ClimbWindows, v => Settings.ClimbWindows = v);
            Toggle("有声音时跳舞", () => Settings.Dance, v => Settings.Dance = v);
            Toggle("节日装扮", () => Settings.Outfits, v => { Settings.Outfits = v; stage.RefreshOutfit(); });
            Toggle("定时举牌提醒", () => Settings.Reminders, v => Settings.Reminders = v);

            // Pip 自己的音量（和系统音量分开）：一个标签 + 一根滑条，松手时出一声试听
            menu.Items.Add(new ToolStripSeparator());
            var volLabel = new ToolStripLabel();
            var bar = new TrackBar { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, SmallChange = 5, LargeChange = 10, Width = 200, AutoSize = false, Height = 28 };
            void SyncVol() { bar.Value = Settings.Volume; volLabel.Text = Settings.Volume == 0 ? "Pip 的声音：静音" : $"Pip 的声音：{Settings.Volume}%"; }
            bar.ValueChanged += (s, e) => { Settings.Volume = bar.Value; volLabel.Text = bar.Value == 0 ? "Pip 的声音：静音" : $"Pip 的声音：{bar.Value}%"; };
            bar.MouseUp += (s, e) => Voice.Play(Cue.Hop, true);
            bar.KeyUp += (s, e) => Voice.Play(Cue.Hop, true);
            menu.Items.Add(volLabel);
            menu.Items.Add(new ToolStripControlHost(bar) { AutoSize = false, Width = 210, Height = 30 });
            menu.Items.Add(new ToolStripSeparator());

            var interval = new ToolStripMenuItem("提醒间隔");
            foreach (var m in new[] { 20, 30, 45, 60, 90 })
            {
                var it = new ToolStripMenuItem(m + " 分钟") { Tag = m };
                it.Click += (s, e) => Settings.ReminderMinutes = (int)((ToolStripMenuItem)s).Tag;
                interval.DropDownItems.Add(it);
            }
            menu.Items.Add(interval);
            var now = new ToolStripMenuItem("现在提醒一下");
            now.Click += (s, e) => stage.RemindNow();
            menu.Items.Add(now);
            menu.Items.Add(new ToolStripSeparator());
            Toggle("开机自动启动", () => RegistryStore.AutoStart, v => RegistryStore.AutoStart = v);
            var upd = new ToolStripMenuItem($"检查更新（现在 {Updater.Current}）");
            upd.Click += (s, e) => Updater.Check(true);
            menu.Items.Add(upd);
            menu.Items.Add(new ToolStripSeparator());
            var quit = new ToolStripMenuItem("退出 Pip");
            quit.Click += (s, e) => Application.Exit();
            menu.Items.Add(quit);

            menu.Opening += (s, e) =>
            {
                hide.Text = stage.IsUserHidden ? "显示小人" : "隐藏小人";
                pause.Checked = stage.IsPaused;
                pause.Text = stage.IsPaused ? "继续动画" : "暂停（停在原地不动）";
                foreach (var t in toggles) t.item.Checked = t.get();
                SyncVol();
                foreach (ToolStripMenuItem it in interval.DropDownItems) it.Checked = (int)it.Tag == Settings.ReminderMinutes;
            };

            stage.Menu = menu;
            tray = new NotifyIcon { Text = "Pip", ContextMenuStrip = menu, Visible = true, Icon = AppIcon() };
            tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) stage.ShowIfHidden(); };
        }

        /// 托盘用 exe 里嵌的 app.ico，按系统小图标尺寸取（高分屏会取 32 或 48 那张）
        static Icon AppIcon()
        {
            try
            {
                using (var st = typeof(Program).Assembly.GetManifestResourceStream("app.ico"))
                    if (st != null) return new Icon(st, SystemInformation.SmallIconSize);
            }
            catch { }
            try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { return SystemIcons.Application; }
        }
    }
}
