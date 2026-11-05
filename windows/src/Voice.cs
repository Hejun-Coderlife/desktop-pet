// Pip 的小声音：和 Mac 版 Voice.swift 同一套合成参数（没有音频文件），音量按 Settings.Volume 单独缩放，和系统音量无关
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
            try { Output(Wav(Samples(cue), vol / 100f)); } catch { }
        }

        public static float[] Samples(Cue cue)
        {
            if (!cache.TryGetValue(cue, out var s)) cache[cue] = s = Render(cue);
            return s;
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

        // MARK: 合成（参数和 Mac 版一一对应）

        static double Lerp(double a, double b, double t) => a + (b - a) * Math.Min(Math.Max(t, 0), 1);
        static double Adsr(double u, double t, double attack, double release) =>
            Math.Min(1, t / attack) * (u < release ? 1 : Math.Max(0, 1 - (u - release) / (1 - release)));

        class Spec
        {
            public double Duration, Gain, Vibrato, Noise;
            public Func<double, double?> Pitch = u => null, Bell = u => null;
            public Func<double, double, double> Env;
        }

        static Spec SpecFor(Cue cue)
        {
            switch (cue)
            {
                case Cue.Grab: return new Spec { Duration = 0.24, Gain = 0.30, Vibrato = 0.01, Pitch = u => Lerp(560, 1020, u / 0.55), Env = (u, t) => Adsr(u, t, 0.012, 0.55) };
                case Cue.Thrown: return new Spec { Duration = 0.30, Gain = 0.24, Vibrato = 0.02, Pitch = u => Lerp(980, 620, u), Env = (u, t) => Adsr(u, t, 0.015, 0.5) };
                case Cue.Hop: return new Spec { Duration = 0.11, Gain = 0.26, Pitch = u => Lerp(880, 1300, u), Env = (u, t) => Adsr(u, t, 0.006, 0.45) };
                case Cue.Land: return new Spec { Duration = 0.13, Gain = 0.42, Noise = 0.35, Pitch = u => Lerp(170, 70, u), Env = (u, t) => Math.Min(1, t / 0.004) * Math.Exp(-u * 5) };
                case Cue.Petted:
                    return new Spec
                    {
                        Duration = 0.50, Gain = 0.22, Vibrato = 0.015,
                        Pitch = u => u < 0.4 ? Lerp(600, 760, u / 0.4) : Lerp(760, 680, (u - 0.4) / 0.6),
                        Env = (u, t) => Adsr(u, t, 0.04, 0.6) * (0.75 + 0.25 * Math.Sin(2 * Math.PI * 11 * t))
                    };
                case Cue.Sign:
                    return new Spec
                    {
                        Duration = 0.80, Gain = 0.20, Bell = u => u < 0.32 ? 1568 : 1175,
                        Env = (u, t) => { double l = u < 0.32 ? t : t - 0.32 * 0.80; return Math.Min(1, l / 0.003) * Math.Exp(-l * 6); }
                    };
                default:
                    return new Spec
                    {
                        Duration = 0.75, Gain = 0.20, Vibrato = 0.01, Noise = 0.12,
                        Pitch = u => u < 0.35 ? Lerp(380, 640, u / 0.35) : Lerp(640, 320, (u - 0.35) / 0.65),
                        Env = (u, t) => Adsr(u, t, 0.08, 0.55)
                    };
            }
        }

        static float[] Render(Cue cue)
        {
            var sp = SpecFor(cue);
            int n = (int)(sp.Duration * SR);
            var o = new float[n];
            double ph = 0, ph2 = 0, lp = 0;
            var rng = new SeededRNG(7);
            for (int i = 0; i < n; i++)
            {
                double t = (double)i / SR, u = t / sp.Duration, s = 0;
                var f = sp.Pitch(u);
                if (f.HasValue)
                {
                    ph += 2 * Math.PI * f.Value * (1 + sp.Vibrato * Math.Sin(2 * Math.PI * 6 * t)) / SR;
                    s += Math.Sin(ph) + 0.28 * Math.Sin(2 * ph) + 0.08 * Math.Sin(3 * ph);
                }
                var fb = sp.Bell(u);
                if (fb.HasValue) { ph2 += 2 * Math.PI * fb.Value / SR; s += Math.Sin(ph2) + 0.35 * Math.Sin(2.76 * ph2); }
                if (sp.Noise > 0) { double white = (double)(rng.Next() % 2001) / 1000 - 1; lp += (white - lp) * 0.08; s += sp.Noise * lp * 3; }
                o[i] = (float)(s * sp.Env(u, t) * sp.Gain);
            }
            return o;
        }
    }
}
