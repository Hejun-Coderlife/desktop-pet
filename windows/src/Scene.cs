// 舞台上的东西：Pip + 脚底阴影 + 跳舞音符（Mac 版 SceneFactory + Stage.applyVisuals 里和窗口无关的那部分）
using System;
using System.Collections.Generic;

namespace Pip
{
    class PetScene
    {
        public PipRig Rig;
        public readonly Node Shadow;
        public readonly List<Node> Notes = new List<Node>();
        public readonly List<Node> Roots = new List<Node>();

        public PetScene(Outfit outfit)
        {
            Rig = new PipRig(outfit);
            Shadow = new Node(Mesh.Plane(60, 20), new Material { Model = Lighting.Constant, Tex = Tex.Shadow(), Blend = true, DoubleSided = true, WritesDepth = false })
            { Name = "pip.shadow", Order = -1, CastsShadow = false };
            uint[] colors = { 0xE88AA0, 0x8AA8E8, 0xE8B86A, 0x9AD0A8 };
            string[] syms = { "♪", "♫", "♪", "♬" };
            for (int i = 0; i < 4; i++)
            {
                var n = new Node(Mesh.Plane(30, 30), new Material { Model = Lighting.Constant, Tex = Tex.Text(syms[i], 90, colors[i], 110, 110), Blend = true, DoubleSided = true, WritesDepth = false })
                { Order = 5, Hidden = true };
                Notes.Add(n);
            }
            Roots.Add(Shadow); Roots.Add(Rig.Root); Roots.AddRange(Notes);
        }

        /// 换装要换一只新的 Pip（Mac 版是重开生效，这里直接换）
        public void Rebuild(Outfit outfit)
        {
            Roots.Remove(Rig.Root);
            Rig = new PipRig(outfit);
            Roots.Insert(1, Rig.Root);
        }

        public void Apply(PetWorld w, double now, float gazeX, float gazeY)
        {
            Rig.SetGaze(gazeX * (float)w.Facing, gazeY);
            Rig.Apply(PetAnimator.PoseFor(w));

            double lift = Math.Max(0, w.Y - w.GroundY);
            double t = Math.Min(1, lift / 240);
            float scale = (float)((1 - 0.42 * t) * (1 + 0.04 * (1 - t)));
            bool lying = w.State == PetState.Sleep;
            Shadow.Pos = new V3((float)(w.X + (lying ? w.Facing * 32 : 0)), (float)w.GroundY + 1.5f, 1);
            Shadow.Scale = new V3(scale * (lying ? 1.9f : 1), scale, scale);
            Shadow.Opacity = (float)(1 - 0.75 * t);

            bool dancing = w.State == PetState.Dance;
            for (int i = 0; i < Notes.Count; i++)
            {
                var n = Notes[i];
                n.Hidden = !dancing;
                if (!dancing) continue;
                double ph = (now * 0.6 + i / 4.0) % 1.0;
                double side = i % 2 == 0 ? -1 : 1;
                n.Pos = new V3((float)(w.X + side * (46 + ph * 14)), (float)(w.Y + 70 + ph * 70), 60);
                n.Opacity = (float)Math.Sin(ph * Math.PI);
                n.Euler = new V3(0, 0, (float)(Math.Sin(now * 3 + i) * 0.3));
            }
        }
    }
}
