// Pip 的小声音：和 Mac 版共用 Resources/sounds/*.wav（tools/make_voice.py 生成，嵌在 exe 里），音量按 Settings.Volume 单独缩放，和系统音量无关
using System;
using System.Collections.Generic;
using System.IO;

namespace Pip
{
    enum Cue { Grab, Thrown, Hop, Land, Petted, Sign, Wake }

    static class Voice
    {
        const int SR = 44100;
        /// 平台播放器：拿到完整的 WAV 字节就放（Windows 上是 winmm PlaySound）
        public static Action<byte[]> Output;
        static readonly Dictionary<Cue, float[]> cache = new Dictionary<Cue, float[]>();
        static readonly Dictionary<Cue, double> lastPlayed = new Dictionary<Cue, double>();
        static readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();

        public static void React(PetState old, PetState now)
        {
            if (now == PetState.Grabbed) Play(Cue.Grab);
            else if (old == PetState.Grabbed && now == PetState.Falling) Play(Cue.Thrown);
            else if (now == PetState.Falling) Play(Cue.Hop);
            else if (old == PetState.Falling && now == PetState.Landing) Play(Cue.Land);
            else if (now == PetState.Petted) Play(Cue.Petted);
            else if (now == PetState.Sign) Play(Cue.Sign);
            else if (old == PetState.Sleep && now == PetState.Wake) Play(Cue.Wake);
        }

        public static void Play(Cue cue, bool force = false)
        {
            int vol = Settings.Volume;
            if (vol <= 0 || Output == null) return;
            double t = clock.Elapsed.TotalSeconds;
            if (!force && lastPlayed.TryGetValue(cue, out var last) && t - last < 0.35) return;
            lastPlayed[cue] = t;
            var x = Samples(cue);
            if (x.Length == 0) return;   // 这个动作还没配声音
            try { Output(Wav(x, vol / 100f)); } catch { }
        }

        public static float[] Samples(Cue cue)
        {
            if (!cache.TryGetValue(cue, out var s)) cache[cue] = s = Load(cue);
            return s;
        }

        /// 读嵌入的 16 位单声道 WAV（找 data 块，不假设头长度）
        static float[] Load(Cue cue)
        {
            using (var st = typeof(Voice).Assembly.GetManifestResourceStream("sounds." + cue.ToString().ToLowerInvariant() + ".wav"))
            {
                if (st == null) return new float[0];
                var r = new BinaryReader(st);
                r.ReadBytes(12);
                while (st.Position + 8 <= st.Length)
                {
                    var id = new string(r.ReadChars(4)); int len = r.ReadInt32();
                    if (id != "data") { r.ReadBytes(len); continue; }
                    var o = new float[len / 2];
                    for (int i = 0; i < o.Length; i++) o[i] = r.ReadInt16() / 32768f;
                    return o;
                }
                return new float[0];
            }
        }

        /// 16 位单声道 WAV
        public static byte[] Wav(float[] x, float gain)
        {
            var ms = new MemoryStream();
            var w = new BinaryWriter(ms);
            int data = x.Length * 2;
            w.Write(new[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' }); w.Write(36 + data);
            w.Write(new[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E', (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
            w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' }); w.Write(data);
            foreach (var v in x) w.Write((short)Math.Max(-32767, Math.Min(32767, v * gain * 32767)));
            w.Flush();
            return ms.ToArray();
        }
    }
}
