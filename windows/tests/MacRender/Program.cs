// Mac 上的渲染测试：CGL 离屏上下文 → 和 Windows 同一份 Renderer → 各状态出一张 PNG（拼成一张对照图）
using System;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using Pip;

static class Cgl
{
    const string Lib = "/System/Library/Frameworks/OpenGL.framework/OpenGL";
    [DllImport(Lib)] static extern int CGLChoosePixelFormat(int[] attribs, out IntPtr pix, out int npix);
    [DllImport(Lib)] static extern int CGLCreateContext(IntPtr pix, IntPtr share, out IntPtr ctx);
    [DllImport(Lib)] static extern int CGLSetCurrentContext(IntPtr ctx);
    [DllImport("/usr/lib/libSystem.dylib")] static extern IntPtr dlopen(string path, int mode);
    [DllImport("/usr/lib/libSystem.dylib")] static extern IntPtr dlsym(IntPtr h, string name);

    public static void Init()
    {
        int[] attrs = { 99, 0x3200, 73, 0 };   // kCGLPFAOpenGLProfile = 3.2 core, kCGLPFAAccelerated
        if (CGLChoosePixelFormat(attrs, out var pix, out _) != 0 || pix == IntPtr.Zero) throw new Exception("CGLChoosePixelFormat");
        if (CGLCreateContext(pix, IntPtr.Zero, out var ctx) != 0) throw new Exception("CGLCreateContext");
        CGLSetCurrentContext(ctx);
        var h = dlopen(Lib, 1);
        var missing = GL.Load(n => dlsym(h, n));
        if (missing != null) throw new Exception("缺少 " + missing);
    }
}

static class Png
{
    static uint[] crcTable;
    static uint Crc(byte[] b, int off, int len)
    {
        if (crcTable == null) { crcTable = new uint[256]; for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; crcTable[n] = c; } }
        uint crc = 0xFFFFFFFF; for (int i = off; i < off + len; i++) crc = crcTable[(crc ^ b[i]) & 0xFF] ^ (crc >> 8); return crc ^ 0xFFFFFFFF;
    }
    static void Chunk(Stream s, string type, byte[] data)
    {
        var len = BitConverter.GetBytes(data.Length); Array.Reverse(len); s.Write(len, 0, 4);
        var buf = new byte[4 + data.Length]; System.Text.Encoding.ASCII.GetBytes(type).CopyTo(buf, 0); data.CopyTo(buf, 4);
        s.Write(buf, 0, buf.Length);
        var crc = BitConverter.GetBytes(Crc(buf, 0, buf.Length)); Array.Reverse(crc); s.Write(crc, 0, 4);
    }
    /// bgra：自下而上、预乘 alpha → 存成普通 RGBA PNG
    public static void Save(string path, byte[] bgra, int w, int h)
    {
        var raw = new MemoryStream();
        for (int y = h - 1; y >= 0; y--)
        {
            raw.WriteByte(0);
            for (int x = 0; x < w; x++)
            {
                int i = (y * w + x) * 4; byte a = bgra[i + 3];
                byte un(byte c) => a == 0 ? (byte)0 : (byte)Math.Min(255, c * 255 / a);
                raw.WriteByte(un(bgra[i + 2])); raw.WriteByte(un(bgra[i + 1])); raw.WriteByte(un(bgra[i])); raw.WriteByte(a);
            }
        }
        var z = new MemoryStream();
        using (var zs = new ZLibStream(z, CompressionLevel.Optimal, true)) { raw.Position = 0; raw.CopyTo(zs); }
        using var f = File.Create(path);
        f.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var ihdr = new byte[13];
        void be(int v, int o) { ihdr[o] = (byte)(v >> 24); ihdr[o + 1] = (byte)(v >> 16); ihdr[o + 2] = (byte)(v >> 8); ihdr[o + 3] = (byte)v; }
        be(w, 0); be(h, 4); ihdr[8] = 8; ihdr[9] = 6;
        Chunk(f, "IHDR", ihdr); Chunk(f, "IDAT", z.ToArray()); Chunk(f, "IEND", new byte[0]);
    }
}

static class Program
{
    static int Main(string[] args)
    {
        string outDir = args.Length > 0 ? args[0] : "/tmp/pip-win-render";
        Directory.CreateDirectory(outDir);
        Cgl.Init();
        var r = new Renderer(); r.Init();
        Console.WriteLine(r.Info);

        // 网格朝向自检：每个三角形的面法线应和顶点法线同向
        CheckWinding();

        var cases = new (string name, PetState s, double t, double phase, double st, string outfit)[]
        {
            ("idle", PetState.Idle, 0.3, 0, 0, "none"),
            ("walk", PetState.Walk, 1, 1.2, 0, "none"),
            ("grabbed", PetState.Grabbed, 0.4, 0, 0, "none"),
            ("sleep", PetState.Sleep, 2, 0, 0, "none"),
            ("dance", PetState.Dance, 0.6, 0, 0, "none"),
            ("petted", PetState.Petted, 0.3, 0, 0, "none"),
            ("halloween", PetState.Idle, 0.3, 0, 0, "halloween"),
            ("christmas", PetState.Idle, 0.3, 0, 0, "christmas"),
            ("newyear", PetState.Idle, 0.3, 0, 0, "newyear"),
        };
        float W = 160, H = 150, scale = args.Length > 1 ? float.Parse(args[1]) : 2;
        foreach (var c in cases)
        {
            Outfits.Override = c.outfit == "halloween" ? Outfit.Halloween : c.outfit == "christmas" ? Outfit.Christmas : c.outfit == "newyear" ? Outfit.NewYear : Outfit.None;
            var scene = new PetScene(Outfits.Current());
            var w = new PetWorld(W, H, 20);
            w.Preview(c.s, c.t, W / 2, 20, c.phase, c.st);
            scene.Apply(w, c.t, 0, 0);
            int pw = (int)Math.Round(W * scale), ph = (int)Math.Round(H * scale);
            var buf = new byte[pw * ph * 4];
            var hnd = GCHandle.Alloc(buf, GCHandleType.Pinned);
            r.Render(scene.Roots, 0, 0, W, H, scale, hnd.AddrOfPinnedObject());
            hnd.Free();
            Png.Save(Path.Combine(outDir, c.name + ".png"), buf, pw, ph);
            Console.WriteLine($"{c.name}: err=0x{GL.GetError():X}");
        }
        return 0;
    }

    static void CheckWinding()
    {
        var meshes = new (string, Mesh)[] {
            ("lathe", Mesh.Lathe(PipRig.BodyProfile, 32)), ("sphere", Mesh.Sphere(5, 24)), ("capsule", Mesh.Capsule(5, 17)),
            ("cone", Mesh.Cone(0.5f, 13, 24)), ("cyl", Mesh.Cylinder(1, 5)), ("torus", Mesh.Torus(12, 3)), ("box", Mesh.Box(2, 3, 4)), ("plane", Mesh.Plane(2, 2)) };
        foreach (var (name, m) in meshes)
        {
            int good = 0, bad = 0;
            for (int i = 0; i < m.Idx.Length; i += 3)
            {
                V3 P(uint k) => new V3(m.Pos[k * 3], m.Pos[k * 3 + 1], m.Pos[k * 3 + 2]);
                V3 N(uint k) => new V3(m.Nor[k * 3], m.Nor[k * 3 + 1], m.Nor[k * 3 + 2]);
                var fn = V3.Cross(P(m.Idx[i + 1]) - P(m.Idx[i]), P(m.Idx[i + 2]) - P(m.Idx[i]));
                if (fn.Length < 1e-6f) continue;
                var vn = N(m.Idx[i]) + N(m.Idx[i + 1]) + N(m.Idx[i + 2]);
                if (V3.Dot(fn, vn) > 0) good++; else bad++;
            }
            Console.WriteLine($"winding {name}: good={good} bad={bad}");
        }
    }
}
