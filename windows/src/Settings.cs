// 开关（托盘菜单里改）。Windows 上存注册表 HKCU\Software\Pip，见 WinSettingsStore；测试时存内存
using System.Collections.Generic;

namespace Pip
{
    interface ISettingsStore
    {
        object Get(string key);
        void Set(string key, object value);
    }

    class MemoryStore : ISettingsStore
    {
        readonly Dictionary<string, object> d = new Dictionary<string, object>();
        public object Get(string k) => d.TryGetValue(k, out var v) ? v : null;
        public void Set(string k, object v) => d[k] = v;
    }

    static class Settings
    {
        public static ISettingsStore Store = new MemoryStore();

        static bool Flag(string k, bool def) { var v = Store.Get(k); return v is int i ? i != 0 : v is bool b ? b : def; }
        static void SetFlag(string k, bool v) => Store.Set(k, v ? 1 : 0);

        public static bool ClimbWindows { get => Flag("climbWindows", true); set => SetFlag("climbWindows", value); }
        public static bool Dance { get => Flag("dance", true); set => SetFlag("dance", value); }
        public static bool Reminders { get => Flag("reminders", true); set => SetFlag("reminders", value); }
        public static bool Outfits { get => Flag("outfitsEnabled", true); set => SetFlag("outfitsEnabled", value); }
        /// 提醒间隔（分钟，按「真的在用电脑」的时间累计）
        public static int ReminderMinutes { get { var v = Store.Get("reminderMinutes"); return v is int i && i > 0 ? i : 45; } set => Store.Set("reminderMinutes", value); }
    }
}
