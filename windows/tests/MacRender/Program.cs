// Mac 上的渲染测试：CGL 离屏上下文 → 和 Windows 同一份 Renderer → 各状态出一张 PNG（拼成一张对照图）
using System;
using System.IO;
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

static class Program
{
    static int Main(string[] args)
    {
        string outDir = args.Length > 0 ? args[0] : "/tmp/pip-win-render";
        if (!outDir.EndsWith(".ico")) Directory.CreateDirectory(outDir);
        Cgl.Init();
        var r = new Renderer(); r.Init();
        Console.WriteLine(r.Info);
        if (outDir.EndsWith(".ico")) { MakeIcon(r, outDir); return 0; }

        // 网格朝向自检：每个三角形的面法线应和顶点法线同向
        CheckWinding();
        var log = new System.Text.StringBuilder();
        bool ok = WorldTests.Run(log);
        Console.Write(log.ToString());
        if (!ok) return 1;

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
            Png.SaveRender(Path.Combine(outDir, c.name + ".png"), buf, pw, ph);
            Console.WriteLine($"{c.name}: err=0x{GL.GetError():X}");
        }
        return 0;
    }

    /// 程序图标：Pip 正面全身，透明底；ICO 里放 256/64/48/32/16 五张 PNG
    static void MakeIcon(Renderer r, string path)
    {
        Outfits.Override = Outfit.None;
        var scene = new PetScene(Outfit.None);
        var w = new PetWorld(200, 200, 0);
        w.Preview(PetState.Idle, 0.3, 100, 4);
        scene.Apply(w, 0.3, 0, 0);
        scene.Shadow.Hidden = true;
        var sizes = new[] { 256, 64, 48, 32, 16 };
        var pngs = new System.Collections.Generic.List<byte[]>();
        foreach (var px in sizes)
        {
            float box = 98;   // 取景：脚底到头顶约 92 点，左右含手臂约 80 点
            float scale = px / box;
            var buf = new byte[px * px * 4];
            var hnd = GCHandle.Alloc(buf, GCHandleType.Pinned);
            r.Render(scene.Roots, 100 - box / 2, 0, box, box, scale, hnd.AddrOfPinnedObject());
            hnd.Free();
            pngs.Add(Png.Encode(Png.FromRender(buf, px, px), px, px));
            if (px == 256) File.WriteAllBytes(Path.ChangeExtension(path, ".png"), pngs[pngs.Count - 1]);
        }
        using var f = File.Create(path);
        var bw = new BinaryWriter(f);
        bw.Write((short)0); bw.Write((short)1); bw.Write((short)sizes.Length);
        int offset = 6 + 16 * sizes.Length;
        for (int i = 0; i < sizes.Length; i++)
        {
            bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i])); bw.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
            bw.Write((byte)0); bw.Write((byte)0); bw.Write((short)1); bw.Write((short)32);
            bw.Write(pngs[i].Length); bw.Write(offset); offset += pngs[i].Length;
        }
        foreach (var p in pngs) bw.Write(p);
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
