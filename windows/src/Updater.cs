// 自动更新：看 GitHub Releases 上最新的版本（仓库公开，不用登录），比自己新就问要不要更新。
// 不用 api.github.com：没登录每个 IP 每小时只给 60 次，代理节点 / 公司网络是很多人共用一个出口，
// 早被别人用完了（2026-11-06 实测 403 rate limit exceeded）。改成：
//   github.com/<仓库>/releases/latest 会 302 跳到 .../releases/tag/v1.2.3 → 从跳转地址拿版本号；
//   安装包 = .../releases/download/v1.2.3/Pip-Setup-1.2.3.exe，旁边的 .sha256 是 CI 写的校验值。
// 点「更新」→ 下载 .sha256 和安装包到 %TEMP%，核对 SHA-256 → 静默安装（Pip.iss 里会先 --quit 旧的、装完再打开）。
// 自动检查：启动 1 分钟后一次，之后每天一次；用户点过「这个版本先不更新」，同一版本自动检查时不再问，托盘菜单「检查更新」照样会问。
// 只在正常运行时启动（--selftest 不联网）。走系统代理（WebClient 默认用 IE / 系统代理设置）。
using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

namespace Pip
{
    static class Updater
    {
        const string Repo = "Hejun-Coderlife/desktop-pet";
        const string Site = "https://github.com/" + Repo + "/releases/";

        static SynchronizationContext ui;
        static System.Windows.Forms.Timer timer;
        static int busy;

        public static Version Current
        {
            get { var v = Assembly.GetExecutingAssembly().GetName().Version; return new Version(v.Major, v.Minor, Math.Max(0, v.Build)); }
        }

        /// 在 UI 线程（托盘建好之后）调用
        public static void Start()
        {
            ui = SynchronizationContext.Current;
            timer = new System.Windows.Forms.Timer { Interval = 60 * 1000 };
            timer.Tick += (s, e) =>
            {
                timer.Interval = 60 * 60 * 1000;   // 之后每小时看一眼是不是该查了（距上次满 24 小时才真的查）
                if ((DateTime.UtcNow - LastCheck).TotalHours >= 24) Check(false);
            };
            timer.Start();
        }

        static DateTime LastCheck
        {
            get { var v = Settings.Store.Get("lastUpdateCheck"); return v is int i && i > 0 ? DateTimeOffset.FromUnixTimeSeconds(i).UtcDateTime : DateTime.MinValue; }
            set => Settings.Store.Set("lastUpdateCheck", (int)new DateTimeOffset(value).ToUnixTimeSeconds());
        }

        class Release { public Version Version; public string Tag, Url; }

        // 设置只能存整数（RegistryStore 一律写 DWORD），版本号编成 主*10000 + 次*100 + 修订
        static int Code(Version v) => v.Major * 10000 + v.Minor * 100 + Math.Max(0, v.Build);
        static int SkipVersion { get => Settings.Store.Get("skipVersion") is int i ? i : 0; set => Settings.Store.Set("skipVersion", value); }

        /// manual = 托盘菜单点的：没有新版 / 出错也要告诉用户
        public static void Check(bool manual)
        {
            if (Interlocked.Exchange(ref busy, 1) == 1) return;
            new Thread(() =>
            {
                try
                {
                    var r = FetchLatest();
                    LastCheck = DateTime.UtcNow;
                    if (r == null || r.Version <= Current)
                    {
                        if (manual) Post(() => MessageBox.Show($"已经是最新版本（{Current}）。", "Pip", MessageBoxButtons.OK, MessageBoxIcon.Information));
                        return;
                    }
                    if (!manual && SkipVersion == Code(r.Version)) return;
                    Post(() => Ask(r));
                }
                catch (Exception e)
                {
                    if (manual) Post(() => MessageBox.Show("检查更新失败：\n\n" + e.Message + "\n\n可能是网络连不上 GitHub，过一会儿再试。", "Pip", MessageBoxButtons.OK, MessageBoxIcon.Warning));
                }
                finally { Interlocked.Exchange(ref busy, 0); }
            }) { IsBackground = true }.Start();
        }

        static void Post(Action a) { if (ui != null) ui.Post(_ => a(), null); else a(); }

        static WebClient Client()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;   // .NET 4.8 默认不一定开 TLS 1.2，GitHub 只认 1.2+
            var wc = new WebClient();
            wc.Headers[HttpRequestHeader.UserAgent] = "Pip-Updater/" + Current;
            wc.Encoding = System.Text.Encoding.UTF8;
            return wc;
        }

        // releases/latest 的 302 跳转地址里带着最新标签；不跟随跳转，只读 Location
        static Release FetchLatest()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            var req = (HttpWebRequest)WebRequest.Create(Site + "latest");
            req.AllowAutoRedirect = false;
            req.Method = "HEAD";
            req.UserAgent = "Pip-Updater/" + Current;
            req.Timeout = 20000;
            string loc;
            using (var resp = (HttpWebResponse)req.GetResponse()) loc = resp.Headers[HttpResponseHeader.Location] ?? "";
            var m = Regex.Match(loc, @"/releases/tag/(v?(\d+)\.(\d+)\.(\d+))$");
            if (!m.Success) return null;   // 还没发过版本时会跳到 releases 列表页
            var v = new Version(int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value), int.Parse(m.Groups[4].Value));
            return new Release { Tag = m.Groups[1].Value, Version = v, Url = Site + "download/" + m.Groups[1].Value + "/Pip-Setup-" + v + ".exe" };
        }

        static void Ask(Release r)
        {
            var res = MessageBox.Show($"Pip 有新版本 {r.Version}（现在是 {Current}）。\n\n现在更新吗？更新时 Pip 会先关掉，装好后自己打开。\n\n「否」= 这个版本先不更新",
                                      "Pip 更新", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
            if (res != DialogResult.Yes) { SkipVersion = Code(r.Version); return; }
            SkipVersion = 0;
            new Thread(() =>
            {
                try
                {
                    string file = Path.Combine(Path.GetTempPath(), "Pip-Setup-" + r.Version + ".exe");
                    string want;
                    using (var wc = Client())
                    {
                        // CI 写的「<sha256>  Pip-Setup-x.y.z.exe」；没有校验文件就不装
                        var sm = Regex.Match(wc.DownloadString(r.Url + ".sha256"), "[0-9a-fA-F]{64}");
                        if (!sm.Success) throw new Exception("这个版本缺少校验文件，先不更新。");
                        want = sm.Value.ToLowerInvariant();
                        wc.DownloadFile(r.Url, file);
                    }
                    string got;
                    using (var sha = SHA256.Create()) using (var fs = File.OpenRead(file))
                        got = BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "").ToLowerInvariant();
                    if (got != want) { try { File.Delete(file); } catch { } throw new Exception("下载的安装包校验不对（可能没下完整），已删掉。"); }
                    // 安装包会先让 Pip 退出（--quit），这里也自己退，免得两边抢
                    Process.Start(new ProcessStartInfo(file, "/SILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
                    Post(() => Application.Exit());
                }
                catch (Exception e)
                {
                    Post(() => MessageBox.Show("更新失败：\n\n" + e.Message, "Pip", MessageBoxButtons.OK, MessageBoxIcon.Warning));
                }
            }) { IsBackground = true }.Start();
        }
    }
}
