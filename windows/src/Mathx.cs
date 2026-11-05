// 向量 / 矩阵 / 场景节点。和 Mac 版 SceneKit 的约定保持一致：
// - 右手坐标，y 向上，相机看 -Z
// - 节点变换 = 平移 · 旋转 · 缩放，旋转 = Rz · Ry · Rx（SceneKit eulerAngles 的实际顺序，已在 Mac 上实测核对）
using System;
using System.Collections.Generic;

namespace Pip
{
    static class F
    {
        public const float PI = (float)Math.PI;
        public static float Sin(float x) => (float)Math.Sin(x);
        public static float Cos(float x) => (float)Math.Cos(x);
        public static float Sqrt(float x) => (float)Math.Sqrt(x);
        public static float Pow(float x, float y) => (float)Math.Pow(x, y);
        public static float Abs(float x) => Math.Abs(x);
        public static float Atan2(float y, float x) => (float)Math.Atan2(y, x);
        public static float Floor(float x) => (float)Math.Floor(x);
        public static float Min(float a, float b) => a < b ? a : b;
        public static float Max(float a, float b) => a > b ? a : b;
        public static float Clamp(float v, float lo, float hi) => v < lo ? lo : (v > hi ? hi : v);
        public static float Hypot(float a, float b) => (float)Math.Sqrt(a * a + b * b);
        /// Swift 的 truncatingRemainder：结果和被除数同号（C# 的 % 就是这样）
        public static float Rem(float a, float b) => a % b;
    }

    struct V3
    {
        public float X, Y, Z;
        public V3(float x, float y, float z) { X = x; Y = y; Z = z; }
        public static V3 operator +(V3 a, V3 b) => new V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
        public static V3 operator -(V3 a, V3 b) => new V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z);
        public static V3 operator *(V3 a, float s) => new V3(a.X * s, a.Y * s, a.Z * s);
        public static V3 operator -(V3 a) => new V3(-a.X, -a.Y, -a.Z);
        public float Length => F.Sqrt(X * X + Y * Y + Z * Z);
        public V3 Normalized { get { var l = Length; return l > 1e-6f ? new V3(X / l, Y / l, Z / l) : new V3(0, 0, 1); } }
        public static float Dot(V3 a, V3 b) => a.X * b.X + a.Y * b.Y + a.Z * b.Z;
        public static V3 Cross(V3 a, V3 b) => new V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X);
        public static readonly V3 One = new V3(1, 1, 1);
        public override string ToString() => $"({X:0.##},{Y:0.##},{Z:0.##})";
    }

    /// 4×4 矩阵，列主序（和 OpenGL uniform 一致）。m[c*4+r]
    struct M4
    {
        public float[] m;
        public static M4 Identity() { var r = new M4 { m = new float[16] }; r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1; return r; }
        public float this[int r, int c] { get => m[c * 4 + r]; set => m[c * 4 + r] = value; }

        public static M4 operator *(M4 a, M4 b)
        {
            var o = new M4 { m = new float[16] };
            for (int c = 0; c < 4; c++)
                for (int r = 0; r < 4; r++)
                {
                    float s = 0;
                    for (int k = 0; k < 4; k++) s += a.m[k * 4 + r] * b.m[c * 4 + k];
                    o.m[c * 4 + r] = s;
                }
            return o;
        }
        public static M4 Translate(V3 t) { var r = Identity(); r[0, 3] = t.X; r[1, 3] = t.Y; r[2, 3] = t.Z; return r; }
        public static M4 Scale(V3 s) { var r = Identity(); r[0, 0] = s.X; r[1, 1] = s.Y; r[2, 2] = s.Z; return r; }
        public static M4 RotX(float a) { var r = Identity(); float c = F.Cos(a), s = F.Sin(a); r[1, 1] = c; r[1, 2] = -s; r[2, 1] = s; r[2, 2] = c; return r; }
        public static M4 RotY(float a) { var r = Identity(); float c = F.Cos(a), s = F.Sin(a); r[0, 0] = c; r[0, 2] = s; r[2, 0] = -s; r[2, 2] = c; return r; }
        public static M4 RotZ(float a) { var r = Identity(); float c = F.Cos(a), s = F.Sin(a); r[0, 0] = c; r[0, 1] = -s; r[1, 0] = s; r[1, 1] = c; return r; }
        public static M4 Euler(V3 e) => RotZ(e.Z) * RotY(e.Y) * RotX(e.X);
        /// 正交投影：x∈[l,r] y∈[b,t] 视线 -Z，near/far 是到相机的距离
        public static M4 Ortho(float l, float r, float b, float t, float n, float f)
        {
            var o = Identity();
            o[0, 0] = 2 / (r - l); o[1, 1] = 2 / (t - b); o[2, 2] = -2 / (f - n);
            o[0, 3] = -(r + l) / (r - l); o[1, 3] = -(t + b) / (t - b); o[2, 3] = -(f + n) / (f - n);
            return o;
        }
        public V3 Point(V3 p) => new V3(this[0, 0] * p.X + this[0, 1] * p.Y + this[0, 2] * p.Z + this[0, 3],
                                        this[1, 0] * p.X + this[1, 1] * p.Y + this[1, 2] * p.Z + this[1, 3],
                                        this[2, 0] * p.X + this[2, 1] * p.Y + this[2, 2] * p.Z + this[2, 3]);
        /// 法线矩阵：左上 3×3 的逆转置（列主序 9 个数）
        public float[] NormalMatrix()
        {
            float a = this[0, 0], b = this[0, 1], c = this[0, 2], d = this[1, 0], e = this[1, 1], f = this[1, 2], g = this[2, 0], h = this[2, 1], i = this[2, 2];
            float A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g;
            float D = -(b * i - c * h), E = a * i - c * g, Fv = -(a * h - b * g);
            float G = b * f - c * e, H = -(a * f - c * d), I = a * e - b * d;
            float det = a * A + b * B + c * C;
            if (Math.Abs(det) < 1e-12f) det = 1e-12f;
            float k = 1 / det;
            // inverse = adj^T / det，逆转置 = 余子式矩阵 / det；列主序写出
            return new[] { A * k, B * k, C * k, D * k, E * k, Fv * k, G * k, H * k, I * k };
        }
    }

    /// 和 SceneKit 节点一样的层级：位置 / 欧拉角 / 缩放 / 透明度 / 隐藏
    class Node
    {
        public string Name;
        public V3 Pos;
        public V3 Euler;
        public V3 Scale = V3.One;
        public float Opacity = 1;
        public bool Hidden;
        public Mesh Mesh;
        public Material Mat;
        public int Order;          // 渲染顺序（SceneKit renderingOrder）
        public bool CastsShadow = true;
        public readonly List<Node> Children = new List<Node>();
        public Node Parent;

        public Node() { }
        public Node(Mesh mesh, Material mat) { Mesh = mesh; Mat = mat; }

        public Node Add(Node c) { c.Parent = this; Children.Add(c); return c; }
        public void RemoveAll() { foreach (var c in Children) c.Parent = null; Children.Clear(); }

        public M4 Local => M4.Translate(Pos) * M4.Euler(Euler) * M4.Scale(Scale);
    }
}
