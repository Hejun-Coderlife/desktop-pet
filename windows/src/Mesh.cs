// 几何体：和 SceneKit 的基础形体（球、胶囊、圆柱、圆锥、圆环、方块、平面）以及 Mac 版的 Lathe / Tube 一一对应。
// 正面 = 逆时针（CCW），和 SceneKit 一样。
using System;
using System.Collections.Generic;

namespace Pip
{
    class Mesh
    {
        public float[] Pos, Nor, UV;     // 每顶点 3/3/2
        public uint[] Idx;
        public object GpuHandle;          // 渲染器缓存的 VAO 等

        public int VertexCount => Pos.Length / 3;

        public static Mesh From(List<V3> p, List<V3> n, List<float> uv, List<uint> idx)
        {
            var m = new Mesh { Pos = new float[p.Count * 3], Nor = new float[p.Count * 3], UV = uv.ToArray(), Idx = idx.ToArray() };
            for (int i = 0; i < p.Count; i++)
            {
                m.Pos[i * 3] = p[i].X; m.Pos[i * 3 + 1] = p[i].Y; m.Pos[i * 3 + 2] = p[i].Z;
                m.Nor[i * 3] = n[i].X; m.Nor[i * 3 + 1] = n[i].Y; m.Nor[i * 3 + 2] = n[i].Z;
            }
            if (m.UV.Length == 0) m.UV = new float[p.Count * 2];
            return m;
        }

        /// 网格面片的通用索引：rows×cols 个格子，顶点按行排列（每行 cols+1 个）。flip 反转朝向
        static void Grid(List<uint> idx, int rows, int cols, uint start, bool flip)
        {
            for (int i = 0; i < rows; i++)
                for (int j = 0; j < cols; j++)
                {
                    uint a = start + (uint)(i * (cols + 1) + j), b = a + 1, c = a + (uint)(cols + 1), d = c + 1;
                    if (!flip) idx.AddRange(new[] { a, c, b, b, c, d });
                    else idx.AddRange(new[] { a, b, c, b, d, c });
                }
        }

        // MARK: Lathe —— 与 Mac 版 Lathe.swift 完全相同（包括索引顺序）
        public static Mesh Lathe((float y, float r)[] profile, int segments)
        {
            var p = new List<V3>(); var n = new List<V3>(); var uv = new List<float>(); var idx = new List<uint>();
            int rows = profile.Length;
            float height = Math.Max(profile[rows - 1].y - profile[0].y, 0.001f);
            for (int i = 0; i < rows; i++)
            {
                var pt = profile[i]; var prev = profile[Math.Max(i - 1, 0)]; var next = profile[Math.Min(i + 1, rows - 1)];
                float dy = next.y - prev.y, dr = next.r - prev.r;
                float ny = -dr, nr = dy; float len = F.Sqrt(ny * ny + nr * nr);
                if (len > 0.0001f) { ny /= len; nr /= len; } else { ny = 1; nr = 0; }
                for (int j = 0; j <= segments; j++)
                {
                    float a = (float)j / segments * 2 * F.PI, ca = F.Cos(a), sa = F.Sin(a);
                    p.Add(new V3(pt.r * ca, pt.y, pt.r * sa));
                    n.Add(new V3(nr * ca, ny, nr * sa));
                    uv.Add((float)j / segments); uv.Add((pt.y - profile[0].y) / height);
                }
            }
            Grid(idx, rows - 1, segments, 0, false);
            return From(p, n, uv, idx);
        }

        // MARK: 绕 Y 轴的旋转体（球 / 胶囊 / 圆柱 / 圆锥都用它），profile 从下到上
        static Mesh Revolve(List<(float y, float r, float ny, float nr, float v)> prof, int seg, bool flip)
        {
            var p = new List<V3>(); var n = new List<V3>(); var uv = new List<float>(); var idx = new List<uint>();
            foreach (var q in prof)
                for (int j = 0; j <= seg; j++)
                {
                    // SceneKit 的球/柱 u 从 -Z 方向开始逆时针；这里只要绕法正确，起点无所谓
                    float a = (float)j / seg * 2 * F.PI, ca = F.Cos(a), sa = F.Sin(a);
                    p.Add(new V3(q.r * sa, q.y, q.r * ca));
                    n.Add(new V3(q.nr * sa, q.ny, q.nr * ca).Normalized);
                    uv.Add((float)j / seg); uv.Add(1 - q.v);
                }
            Grid(idx, prof.Count - 1, seg, 0, flip);
            return From(p, n, uv, idx);
        }

        public static Mesh Sphere(float radius, int seg = 48)
        {
            var prof = new List<(float, float, float, float, float)>();
            int rings = seg / 2;
            for (int i = 0; i <= rings; i++)
            {
                float t = (float)i / rings, phi = -F.PI / 2 + t * F.PI;
                prof.Add((F.Sin(phi) * radius, F.Cos(phi) * radius, F.Sin(phi), F.Cos(phi), t));
            }
            return Revolve(prof, seg, true);
        }

        /// 胶囊：height 是含两头半球的总高（SceneKit 定义）
        public static Mesh Capsule(float radius, float height, int radial = 40, int capSeg = 16)
        {
            var prof = new List<(float, float, float, float, float)>();
            float half = Math.Max(0, height / 2 - radius);
            for (int i = 0; i <= capSeg; i++)
            {
                float phi = -F.PI / 2 + (float)i / capSeg * F.PI / 2;
                prof.Add((-half + F.Sin(phi) * radius, F.Cos(phi) * radius, F.Sin(phi), F.Cos(phi), 0));
            }
            for (int i = 0; i <= capSeg; i++)
            {
                float phi = (float)i / capSeg * F.PI / 2;
                prof.Add((half + F.Sin(phi) * radius, F.Cos(phi) * radius, F.Sin(phi), F.Cos(phi), 0));
            }
            for (int i = 0; i < prof.Count; i++) { var q = prof[i]; prof[i] = (q.Item1, q.Item2, q.Item3, q.Item4, (q.Item1 + height / 2) / height); }
            return Revolve(prof, radial, true);
        }

        /// 圆柱 / 圆锥（含上下盖）。居中，高度方向 y
        public static Mesh Cone(float topR, float bottomR, float height, int seg = 48)
        {
            float h2 = height / 2;
            float slope = (bottomR - topR) / height;            // 侧面法线的 y 分量方向
            float nl = F.Sqrt(1 + slope * slope);
            var side = new List<(float, float, float, float, float)>
            {
                (-h2, bottomR, slope / nl, 1 / nl, 0),
                (h2, topR, slope / nl, 1 / nl, 1)
            };
            var m = Revolve(side, seg, true);
            var parts = new List<Mesh> { m };
            if (bottomR > 0) parts.Add(Disc(-h2, bottomR, seg, false));
            if (topR > 0) parts.Add(Disc(h2, topR, seg, true));
            return Merge(parts);
        }
        public static Mesh Cylinder(float r, float height, int seg = 48) => Cone(r, r, height, seg);

        static Mesh Disc(float y, float r, int seg, bool up)
        {
            var p = new List<V3> { new V3(0, y, 0) }; var n = new List<V3> { new V3(0, up ? 1 : -1, 0) }; var uv = new List<float> { 0.5f, 0.5f };
            var idx = new List<uint>();
            for (int j = 0; j <= seg; j++)
            {
                float a = (float)j / seg * 2 * F.PI;
                p.Add(new V3(r * F.Sin(a), y, r * F.Cos(a))); n.Add(new V3(0, up ? 1 : -1, 0)); uv.Add(0); uv.Add(0);
            }
            for (int j = 1; j <= seg; j++)
            {
                if (up) idx.AddRange(new uint[] { 0, (uint)j, (uint)j + 1 });
                else idx.AddRange(new uint[] { 0, (uint)j + 1, (uint)j });
            }
            return From(p, n, uv, idx);
        }

        /// 圆环：躺在 XZ 平面里（SceneKit SCNTorus）
        public static Mesh Torus(float ring, float pipe, int ringSeg = 48, int pipeSeg = 24)
        {
            var p = new List<V3>(); var n = new List<V3>(); var uv = new List<float>(); var idx = new List<uint>();
            for (int i = 0; i <= pipeSeg; i++)
            {
                float b = (float)i / pipeSeg * 2 * F.PI;
                for (int j = 0; j <= ringSeg; j++)
                {
                    float a = (float)j / ringSeg * 2 * F.PI;
                    var dir = new V3(F.Sin(a), 0, F.Cos(a));
                    var nn = dir * F.Cos(b) + new V3(0, F.Sin(b), 0);
                    p.Add(dir * ring + nn * pipe); n.Add(nn);
                    uv.Add((float)j / ringSeg); uv.Add((float)i / pipeSeg);
                }
            }
            Grid(idx, pipeSeg, ringSeg, 0, true);
            return From(p, n, uv, idx);
        }

        /// 方块（不做倒角，挂件上那点倒角在 90 点高的小人上看不出来）
        public static Mesh Box(float w, float h, float l)
        {
            var p = new List<V3>(); var n = new List<V3>(); var uv = new List<float>(); var idx = new List<uint>();
            void Face(V3 nn, V3 u, V3 v)
            {
                uint s = (uint)p.Count;
                var c = new V3(nn.X * w / 2, nn.Y * h / 2, nn.Z * l / 2);
                var du = new V3(u.X * w / 2, u.Y * h / 2, u.Z * l / 2); var dv = new V3(v.X * w / 2, v.Y * h / 2, v.Z * l / 2);
                p.Add(c - du - dv); p.Add(c + du - dv); p.Add(c + du + dv); p.Add(c - du + dv);
                for (int k = 0; k < 4; k++) { n.Add(nn); uv.Add(0); uv.Add(0); }
                idx.AddRange(new[] { s, s + 1, s + 2, s, s + 2, s + 3 });
            }
            Face(new V3(0, 0, 1), new V3(1, 0, 0), new V3(0, 1, 0));
            Face(new V3(0, 0, -1), new V3(-1, 0, 0), new V3(0, 1, 0));
            Face(new V3(1, 0, 0), new V3(0, 0, -1), new V3(0, 1, 0));
            Face(new V3(-1, 0, 0), new V3(0, 0, 1), new V3(0, 1, 0));
            Face(new V3(0, 1, 0), new V3(1, 0, 0), new V3(0, 0, -1));
            Face(new V3(0, -1, 0), new V3(1, 0, 0), new V3(0, 0, 1));
            return From(p, n, uv, idx);
        }

        /// XY 平面里的矩形，朝 +Z；uv 左上 (0,0)（和 SceneKit SCNPlane 一样）
        public static Mesh Plane(float w, float h)
        {
            var p = new List<V3> { new V3(-w / 2, -h / 2, 0), new V3(w / 2, -h / 2, 0), new V3(w / 2, h / 2, 0), new V3(-w / 2, h / 2, 0) };
            var n = new List<V3> { new V3(0, 0, 1), new V3(0, 0, 1), new V3(0, 0, 1), new V3(0, 0, 1) };
            var uv = new List<float> { 0, 1, 1, 1, 1, 0, 0, 0 };
            return From(p, n, uv, new List<uint> { 0, 1, 2, 0, 2, 3 });
        }

        /// 沿一串点扫出圆管（Mac 版 Tube.swift），两端圆头另外加球
        public static Mesh Tube(List<V3> pts, float radius, int sides = 10)
        {
            var p = new List<V3>(); var n = new List<V3>(); var uv = new List<float>(); var idx = new List<uint>();
            int cnt = pts.Count;
            for (int i = 0; i < cnt; i++)
            {
                var t = (pts[Math.Min(i + 1, cnt - 1)] - pts[Math.Max(i - 1, 0)]).Normalized;
                var u = V3.Cross(t, new V3(0, 0, 1)).Normalized;
                var w = V3.Cross(u, t).Normalized;
                for (int s = 0; s < sides; s++)
                {
                    float a = (float)s / sides * 2 * F.PI;
                    var dir = u * F.Cos(a) + w * F.Sin(a);
                    p.Add(pts[i] + dir * radius); n.Add(dir); uv.Add(0); uv.Add(0);
                }
            }
            for (int i = 0; i < cnt - 1; i++)
                for (int s = 0; s < sides; s++)
                {
                    uint a = (uint)(i * sides + s), b = (uint)(i * sides + (s + 1) % sides), c = a + (uint)sides, d = b + (uint)sides;
                    idx.AddRange(new[] { a, c, b, b, c, d });
                }
            var parts = new List<Mesh> { From(p, n, uv, idx) };
            foreach (var e in new[] { pts[0], pts[cnt - 1] })
            {
                var cap = Sphere(radius, 12);
                for (int k = 0; k < cap.VertexCount; k++) { cap.Pos[k * 3] += e.X; cap.Pos[k * 3 + 1] += e.Y; cap.Pos[k * 3 + 2] += e.Z; }
                parts.Add(cap);
            }
            return Merge(parts);
        }

        /// 任意网格（脸片）
        public static Mesh Raw(List<V3> p, List<V3> n, List<float> uv, List<uint> idx) => From(p, n, uv, idx);

        public static Mesh Merge(List<Mesh> parts)
        {
            var pos = new List<float>(); var nor = new List<float>(); var uv = new List<float>(); var idx = new List<uint>();
            foreach (var m in parts)
            {
                uint b = (uint)(pos.Count / 3);
                pos.AddRange(m.Pos); nor.AddRange(m.Nor); uv.AddRange(m.UV);
                foreach (var i in m.Idx) idx.Add(i + b);
            }
            return new Mesh { Pos = pos.ToArray(), Nor = nor.ToArray(), UV = uv.ToArray(), Idx = idx.ToArray() };
        }
    }

    enum Lighting { Lambert, Blinn, Constant, Fur }

    /// 材质：只做 Pip 用得到的那几种
    class Material
    {
        public Lighting Model = Lighting.Lambert;
        public V3 Color = V3.One;           // sRGB（0…1），渲染时转线性
        public float Alpha = 1;             // transparency
        public Texture Tex;                 // diffuse 贴图（sRGB，预乘 alpha）
        public bool Blend;                  // blendMode = alpha
        public bool DoubleSided;
        public bool WritesDepth = true;
        public bool ReadsDepth = true;
        public float Specular;              // blinn 高光强度
        // 绒毛
        public float FurH, FurLen;
        public V3 FurRoot, FurTip, FurRim;  // 注意：Mac 版直接把 sRGB 分量当线性值传进着色器，这里照抄
        public float[] FaceHole = new float[4];
        public float TileU = 1, TileV = 1;
    }

    /// CPU 端的贴图（RGBA8，行从上到下），渲染器第一次用时上传
    class Texture
    {
        public int W, H;
        public byte[] Rgba;
        public bool Mipmap, Repeat, Gray;
        public object GpuHandle;
        public bool Dirty = true;
    }
}
