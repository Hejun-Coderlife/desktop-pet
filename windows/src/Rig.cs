// Pip 的模型和姿势应用：逐项对应 Mac 版 PipRig.swift / Fur.swift / Outfit.swift
using System;
using System.Collections.Generic;

namespace Pip
{
    static class Palette
    {
        public static readonly V3 Fur = Tex.Hex(0xE4D7C5);
        public static readonly V3 FurRoot = Tex.Hex(0xD4C3B9);
        public static readonly V3 FurTip = Tex.Hex(0xF6EEE9);
        public static readonly V3 FurRim = Tex.Hex(0xFFF3EE);
        public static readonly V3 Cheek = Tex.Hex(0xF2A7A7);
        public static readonly V3 Eye = Tex.Hex(0x17191F);
        public static readonly V3 Shine = Tex.Hex(0xEAF2FF);
        public static readonly V3 Mouth = Tex.Hex(0x3A3330);
    }

    /// 壳层绒毛：节点自己变成第 0 层，再叠 layers 层外壳子节点（Fur.apply）
    static class FurBuilder
    {
        public static int DefaultLayers = 14;
        static Texture strands;
        public static Texture StrandTex => strands ?? (strands = Tex.Strands());

        public static void Apply(Node node, float length, float tileU, float tileV, int layers = -1, float[] faceHole = null)
        {
            if (layers < 0) layers = DefaultLayers;
            node.Mat = Make(0, length, tileU, tileV, faceHole);
            for (int i = 1; i <= Math.Max(1, layers); i++)
            {
                var shell = new Node(node.Mesh, Make((float)i / layers, length, tileU, tileV, faceHole)) { Name = "fur.shell." + i, CastsShadow = false };
                node.Add(shell);
            }
        }

        static Material Make(float h, float len, float tu, float tv, float[] hole) => new Material
        {
            Model = Lighting.Fur, FurH = h, FurLen = len, TileU = tu, TileV = tv, Tex = StrandTex,
            FurRoot = Palette.FurRoot, FurTip = Palette.FurTip, FurRim = Palette.FurRim,
            FaceHole = hole ?? new float[4], Color = Palette.FurRoot
        };
    }

    enum Outfit { None, Halloween, Christmas, NewYear }

    static class Outfits
    {
        public static Outfit? Override;

        public static Outfit Current(DateTime? when = null)
        {
            if (Override.HasValue) return Override.Value;
            var env = Environment.GetEnvironmentVariable("PIP_OUTFIT");
            if (!string.IsNullOrEmpty(env))
                switch (env.ToLowerInvariant())
                {
                    case "halloween": return Outfit.Halloween;
                    case "christmas": return Outfit.Christmas;
                    case "newyear": return Outfit.NewYear;
                    case "none": return Outfit.None;
                }
            if (!Settings.Outfits) return Outfit.None;
            var d = when ?? DateTime.Now;
            if ((d.Month == 10 && d.Day >= 24) || (d.Month == 11 && d.Day <= 1)) return Outfit.Halloween;
            if (d.Month == 12 && d.Day >= 15 && d.Day <= 26) return Outfit.Christmas;
            // 春节：农历腊月二十三 ～ 正月十五（闰月不算）
            try
            {
                var cal = new System.Globalization.ChineseLunisolarCalendar();
                int y = cal.GetYear(d), m = cal.GetMonth(d), day = cal.GetDayOfMonth(d);
                int leap = cal.GetLeapMonth(y);
                bool isLeap = leap > 0 && m == leap;
                if (leap > 0 && m >= leap) m -= 1;
                int months = cal.GetMonthsInYear(y) - (leap > 0 ? 1 : 0);
                if (!isLeap && ((m == months && day >= 23) || (m == 1 && day <= 15))) return Outfit.NewYear;
            }
            catch { }
            return Outfit.None;
        }

        static Material Mat(uint hex, bool shiny = false) => new Material
        {
            Model = shiny ? Lighting.Blinn : Lighting.Lambert, Color = Tex.Hex(hex), Specular = shiny ? 0.35f : 0
        };

        public static void Attach(Outfit o, Node head, Node body)
        {
            switch (o)
            {
                case Outfit.Halloween: head.Add(Pumpkin()); break;
                case Outfit.Christmas: head.Add(Santa()); break;
                case Outfit.NewYear: body.Add(Scarf()); break;
            }
        }

        static Node Pumpkin()
        {
            var root = new Node { Pos = new V3(0, 30, -14), Euler = new V3(-0.15f, 0, 0.12f) };
            var orange = Mat(0xF08A24, true);
            var lobeMesh = Mesh.Sphere(8);
            for (int i = 0; i < 6; i++)
            {
                float a = i / 6f * 2 * F.PI;
                root.Add(new Node(lobeMesh, orange) { Scale = new V3(0.75f, 0.82f, 0.75f), Pos = new V3(F.Cos(a) * 5.5f, 0, F.Sin(a) * 5.5f) });
            }
            root.Add(new Node(Mesh.Cylinder(1.6f, 5), Mat(0x4E7A35)) { Pos = new V3(0, 7.5f, 0), Euler = new V3(0, 0, 0.25f) });
            root.Add(new Node(Mesh.Sphere(3), Mat(0x6A9E45)) { Scale = new V3(1.3f, 0.3f, 0.8f), Pos = new V3(3, 7, 1) });
            return root;
        }

        static Node Santa()
        {
            var root = new Node { Pos = new V3(0, 27, -14), Euler = new V3(-0.2f, 0, -0.35f) };
            root.Add(new Node(Mesh.Cone(0.5f, 13, 24), Mat(0xD7263D)) { Pos = new V3(0, 12, 0) });
            root.Add(new Node(Mesh.Torus(12.5f, 3.4f), Mat(0xF8F4EE)));
            root.Add(new Node(Mesh.Sphere(3.6f), Mat(0xF8F4EE)) { Pos = new V3(0, 24.5f, 0) });
            return root;
        }

        static Node Scarf()
        {
            var root = new Node();
            var red = Mat(0xC8102E);
            root.Add(new Node(Mesh.Torus(30.5f, 6.8f, 64, 24), red) { Pos = new V3(0, 33, 0), Scale = new V3(1, 0.85f, 1) });
            root.Add(new Node(Mesh.Box(11, 22, 4), red) { Pos = new V3(13, 21, 35), Euler = new V3(0.1f, 0, 0.18f) });
            root.Add(new Node(Mesh.Box(11, 3.5f, 4.2f), Mat(0xF2C14E)) { Pos = new V3(15, 9.5f, 35.3f), Euler = new V3(0.1f, 0, 0.18f) });
            return root;
        }
    }

    /// Q 版绒毛小人 Pip
    class PipRig
    {
        public readonly Node Root = new Node { Name = "pip.root" };
        public const float PixelHeight = 92;

        const float FaceWidth = 42, FaceHeight = 34, FaceCenterY = 60, FaceLiftBase = 0.5f, FaceBulge = 1.3f;

        public static readonly (float y, float r)[] BodyProfile =
        {
            (5.0f, 0), (5.5f, 7.0f), (7.0f, 14.0f), (10.0f, 20.5f), (14.0f, 25.0f),
            (19.0f, 28.0f), (25.0f, 29.5f), (32.0f, 30.0f), (39.0f, 30.0f), (46.0f, 29.5f),
            (52.0f, 28.5f), (58.0f, 27.0f), (64.0f, 24.3f), (68.0f, 24.0f), (72.0f, 23.2f),
            (76.0f, 21.5f), (80.0f, 18.8f), (83.0f, 15.4f), (85.0f, 11.6f), (86.5f, 6.8f),
            (87.0f, 0)
        };

        public static float BodyRadius(float y)
        {
            var p = BodyProfile;
            if (y <= p[0].y) return p[0].r;
            for (int i = 1; i < p.Length; i++)
                if (y <= p[i].y)
                {
                    float t = (y - p[i - 1].y) / Math.Max(0.0001f, p[i].y - p[i - 1].y);
                    return p[i - 1].r + (p[i].r - p[i - 1].r) * t;
                }
            return p[p.Length - 1].r;
        }

        static V3 SurfacePoint(float x, float y, float lift)
        {
            float r = BodyRadius(y) + lift;
            return new V3(x, y, F.Sqrt(Math.Max(0, r * r - x * x)));
        }

        static float FaceLift(float x, float y)
        {
            float dx = Math.Abs(x / (FaceWidth / 2)), dy = Math.Abs((y - FaceCenterY) / (FaceHeight / 2));
            float r = F.Pow(F.Pow(dx, 2.35f) + F.Pow(dy, 2.35f), 1 / 2.35f);
            float t = Math.Max(0, 1 - r * r);
            return FaceLiftBase + FaceBulge * F.Sqrt(t);
        }

        static void Stick(Node n, float x, float y, float lift)
        {
            var p = SurfacePoint(x, y, lift);
            n.Pos = p;
            n.Euler = new V3(n.Euler.X, F.Atan2(x, Math.Max(0.001f, p.Z)), n.Euler.Z);
        }

        readonly Node squash = new Node(), bodyGroup = new Node(), headPivot = new Node(), headGroup = new Node();
        readonly Node eyeL = new Node(), eyeR = new Node();
        readonly Node armL = new Node(), armR = new Node(), legL = new Node(), legR = new Node();
        readonly List<Node> blush = new List<Node>();
        readonly Node unmirrored = new Node(), zzzHolder = new Node(), signNode = new Node();
        readonly List<Node> zzz = new List<Node>();
        string signShown;
        float gx, gy;
        const float LegBaseY = 12;
        static readonly (float x, float y) EyeBaseL = (-10.6f, 61), EyeBaseR = (10.6f, 61);

        public PipRig(Outfit outfit)
        {
            Root.Add(squash); squash.Add(bodyGroup);

            var body = new Node(Mesh.Lathe(BodyProfile, 96), null) { Name = "body" };
            FurBuilder.Apply(body, 3.3f, 9, 3.9f, 20, new[] { 0, FaceCenterY, FaceWidth / 2, FaceHeight / 2 });
            bodyGroup.Add(body);

            BuildLeg(legL, -9); BuildLeg(legR, 9);
            BuildArm(armL, -26, -1); BuildArm(armR, 26, 1);
            BuildHead();
            BuildExtras();
            var anchor = new Node { Pos = new V3(0, 60, 18) };
            bodyGroup.Add(anchor);
            Outfits.Attach(outfit, anchor, bodyGroup);
        }

        static Material Smooth(V3 c) => new Material { Model = Lighting.Lambert, Color = c };

        void BuildExtras()
        {
            bodyGroup.Add(unmirrored);
            Root.Add(zzzHolder);
            var ztex = Tex.Text("z", 64, 0x6E7FA8, 64, 64);
            for (int i = 0; i < 3; i++)
            {
                float s = 9 + i * 3;
                var n = new Node(Mesh.Plane(s, s), new Material { Model = Lighting.Constant, Tex = ztex, Blend = true, DoubleSided = true, WritesDepth = false }) { Hidden = true };
                zzzHolder.Add(n); zzz.Add(n);
            }
            signNode.Hidden = true;
            unmirrored.Add(signNode);
        }

        void UpdateSign(string text)
        {
            if (text == signShown) return;
            signShown = text;
            signNode.RemoveAll();
            if (text == null) { signNode.Hidden = true; return; }
            var tex = Tex.Text(text, text.Length <= 2 ? 120 : 46, 0x5A4636, 384, 180, 0xFFF7EA);
            var board = new Node(Mesh.Plane(64, 30), new Material { Model = Lighting.Constant, Tex = tex, Blend = true, DoubleSided = true });
            var stickMat = Smooth(Tex.Hex(0xB89C7E));
            var stickMesh = Mesh.Cylinder(0.9f, 14, 12);
            foreach (var x in new[] { -16f, 16f }) board.Add(new Node(stickMesh, stickMat) { Pos = new V3(x, -20, -0.5f) });
            signNode.Add(board);
            signNode.Pos = new V3(0, 116, 26);
            signNode.Hidden = false;
        }

        void BuildLeg(Node pivot, float x)
        {
            pivot.Pos = new V3(x, 12, 0);
            bodyGroup.Add(pivot);
            pivot.Add(new Node(Mesh.Capsule(5, 10), Smooth(Palette.Fur)) { Pos = new V3(0, -4, 0) });
            var foot = new Node(Mesh.Sphere(5.6f, 64), null) { Scale = new V3(1.05f, 0.68f, 1.25f), Pos = new V3(0, -8.4f, 1.6f) };
            FurBuilder.Apply(foot, 1.3f, 1.2f, 0.6f);
            pivot.Add(foot);
        }

        void BuildArm(Node pivot, float x, float sign)
        {
            pivot.Pos = new V3(x * 1.04f, 44, 2);
            bodyGroup.Add(pivot);
            var arm = new Node(Mesh.Capsule(6.2f, 17), null) { Pos = new V3(sign * 4, -6, 0), Euler = new V3(0, 0, sign * 0.45f) };
            FurBuilder.Apply(arm, 2.2f, 1.6f, 1.0f, 16);
            pivot.Add(arm);
        }

        void BuildHead()
        {
            bodyGroup.Add(headPivot); headPivot.Add(headGroup);
            headGroup.Add(FacePanel());
            var eyeMat = new Material { Model = Lighting.Blinn, Color = Palette.Eye, Specular = 0.9f };
            var eyeMesh = Mesh.Sphere(2.35f, 48);
            foreach (var (g, sign) in new[] { (eyeL, -1f), (eyeR, 1f) })
            {
                Stick(g, sign * 10.6f, 61, FaceLift(sign * 10.6f, 61) + 0.7f);
                g.Add(new Node(eyeMesh, eyeMat) { Scale = new V3(0.95f, 0.98f, 0.5f) });
                g.Add(new Node(Mesh.Sphere(0.55f, 24), Smooth(Tex.Hex(0x5C7FA8))) { Scale = new V3(1.4f, 0.6f, 0.4f), Pos = new V3(sign * 0.4f, -1.3f, 0.9f) });
                g.Add(new Node(Mesh.Sphere(0.6f, 24), Smooth(Palette.Shine)) { Pos = new V3(sign * -0.55f, 0.75f, 1.0f) });
                headGroup.Add(g);
            }
            var btex = Tex.Blush();
            foreach (var sign in new[] { -1f, 1f })
            {
                var b = new Node(Mesh.Plane(12.5f, 12.5f * 0.72f), new Material { Model = Lighting.Constant, Tex = btex, Blend = true, DoubleSided = true, WritesDepth = false });
                Stick(b, sign * 12.6f, 55.5f, FaceLift(sign * 12.6f, 55.5f) + 0.2f);
                blush.Add(b); headGroup.Add(b);
            }
            headGroup.Add(MouthNode());
        }

        Node MouthNode()
        {
            float hw = 2.7f, topY = 0.8f, dipY = -1.2f;
            var pts = new List<V3>();
            for (int i = 0; i <= 24; i++)
            {
                float t = i / 24f, om = 1 - t;
                float x = om * om * -hw + t * t * hw;
                float y = -4.2f + om * om * topY + 2 * om * t * dipY + t * t * topY;
                float yy = FaceCenterY - 1.5f + y;
                pts.Add(SurfacePoint(x, yy, FaceLift(x, yy) + 0.3f));
            }
            return new Node(Mesh.Tube(pts, 0.36f), Smooth(Palette.Mouth));
        }

        Node FacePanel()
        {
            int cols = 28, rows = 28;
            var pos = new List<V3>(); var nor = new List<V3>(); var uv = new List<float>();
            for (int j = 0; j <= rows; j++)
                for (int i = 0; i <= cols; i++)
                {
                    float u = (float)i / cols, v = (float)j / rows;
                    float x = (u - 0.5f) * FaceWidth, y = FaceCenterY + (0.5f - v) * FaceHeight;
                    pos.Add(SurfacePoint(x, y, FaceLift(x, y))); nor.Add(new V3(0, 0, 1)); uv.Add(u); uv.Add(v);
                }
            int W = cols + 1;
            for (int j = 0; j <= rows; j++)
                for (int i = 0; i <= cols; i++)
                {
                    var l = pos[j * W + Math.Max(i - 1, 0)]; var r = pos[j * W + Math.Min(i + 1, cols)];
                    var up = pos[Math.Max(j - 1, 0) * W + i]; var dn = pos[Math.Min(j + 1, rows) * W + i];
                    var n = V3.Cross(r - l, up - dn).Normalized;
                    if (n.Z < 0) n = -n;
                    nor[j * W + i] = n;
                }
            for (int it = 0; it < 10; it++)
            {
                var sm = new List<V3>(nor);
                for (int j = 0; j <= rows; j++)
                    for (int i = 0; i <= cols; i++)
                    {
                        var acc = new V3(0, 0, 0);
                        foreach (var (dj, di) in new[] { (0, 0), (-1, 0), (1, 0), (0, -1), (0, 1) })
                        {
                            int jj = Math.Min(Math.Max(j + dj, 0), rows), ii = Math.Min(Math.Max(i + di, 0), cols);
                            acc = acc + nor[jj * W + ii];
                        }
                        sm[j * W + i] = acc.Normalized;
                    }
                nor = sm;
            }
            for (int k = 0; k < nor.Count; k++) { var n = nor[k]; nor[k] = new V3(n.X * 0.45f, n.Y * 0.45f, n.Z + 0.6f).Normalized; }
            var idx = new List<uint>();
            for (int j = 0; j < rows; j++)
                for (int i = 0; i < cols; i++)
                {
                    uint a = (uint)(j * W + i), b = a + 1, c = a + (uint)W, d = c + 1;
                    idx.AddRange(new[] { a, c, b, b, c, d });
                }
            return new Node(Mesh.Raw(pos, nor, uv, idx), new Material { Model = Lighting.Lambert, Tex = Tex.Face(), Blend = true, DoubleSided = true, WritesDepth = false }) { Name = "face" };
        }

        public void SetGaze(float x, float y) { gx = x; gy = y; }

        public void Apply(Pose p)
        {
            Root.Pos = new V3((float)p.FeetX, (float)p.FeetY, 0);
            Root.Scale = new V3((float)p.Facing, 1, 1);
            float sy = Math.Max(0.35f, (float)p.SquashY), sxz = 1 / F.Sqrt(sy);
            squash.Scale = new V3(sxz, sy, sxz);
            bodyGroup.Pos = new V3(0, (float)p.Bob, 0);
            float look = Math.Min(1, F.Hypot(gx, gy));
            bodyGroup.Euler = new V3((float)p.HeadPitch * 0.5f - gy * 0.16f,
                                     (float)p.BodyYaw + (float)p.HeadYaw * 0.5f * (1 - look) + gx * 0.38f,
                                     -(float)p.BodyLean - gx * 0.08f - (float)p.HeadTilt * 0.6f * (1 - look * 0.5f));
            armL.Euler = new V3(0, 0, -(float)p.ArmLeft);
            armR.Euler = new V3(0, 0, (float)p.ArmRight);
            legL.Euler = new V3((float)p.LegLeft, 0, -(float)p.LegSideLeft);
            legR.Euler = new V3((float)p.LegRight, 0, (float)p.LegSideRight);
            legL.Pos = new V3(legL.Pos.X, LegBaseY + (float)p.LiftLeft, legL.Pos.Z);
            legR.Pos = new V3(legR.Pos.X, LegBaseY + (float)p.LiftRight, legR.Pos.Z);

            float open = Math.Max(0.08f, 1 - (float)p.Blink * 0.95f) * (1 - (float)p.HappyEyes * 0.78f);
            float es = (float)p.EyeScale;
            var eyeScale = new V3(es * (1 + (float)p.HappyEyes * 0.25f), es * open, es);
            eyeL.Scale = eyeScale; eyeR.Scale = eyeScale;
            foreach (var b in blush) b.Opacity = Math.Min(1, 0.55f * (float)p.Blush);

            unmirrored.Scale = new V3((float)p.Facing, 1, 1);
            for (int i = 0; i < zzz.Count; i++)
            {
                var n = zzz[i];
                n.Scale = new V3((float)p.Facing, 1, 1);
                if (p.Zzz < 0) { n.Hidden = true; continue; }
                float phase = F.Rem((float)p.Zzz * 0.45f + i / 3f, 1);
                n.Hidden = false;
                n.Pos = new V3(76 + phase * 14, 60 + phase * 34, 40);
                n.Opacity = F.Sin(phase * F.PI);
            }
            UpdateSign(p.Sign);

            float lx = gx * 4.6f, ly = gy * 3.2f;
            foreach (var (g, b) in new[] { (eyeL, EyeBaseL), (eyeR, EyeBaseR) })
            {
                float ex = b.x + lx, ey = b.y + ly;
                Stick(g, ex, ey, FaceLift(ex, ey) + 0.7f);
            }
        }
    }
}
