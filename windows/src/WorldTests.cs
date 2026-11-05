// 状态机自检（Mac 版 SelfTest.swift 的移植）：两次拎起抛出 + 撞墙反弹 + 落地 + 自己跳上旁边的小窗口
using System;
using System.Collections.Generic;
using System.Text;

namespace Pip
{
    static class WorldTests
    {
        public static bool JumpTest(StringBuilder log)
        {
            var w = new PetWorld(1470, 956, 56, 42);
            w.SetPlatform(null);
            w.SetPlatforms(new List<Platform> { new Platform(7, 700, 900, 420) });
            w.IdleSeconds = 0;
            for (int step = 0; step < 30 * 60; step++)
            {
                w.Update(1.0 / 60);
                if (w.OnPlatform && w.Standing.Value.Id == 7 && Math.Abs(w.Y - 420) < 0.5)
                {
                    log.AppendLine($"  [通过] 第 {step / 60.0:0.0} 秒自己跳上了旁边的小窗口");
                    return true;
                }
            }
            log.AppendLine($"  [失败] 30 秒内没跳上小窗口，最后位置 x={w.X:0} y={w.Y:0}");
            return false;
        }

        public static bool Run(StringBuilder log)
        {
            bool jumped = JumpTest(log);
            double W = 1600, H = 900, ground = 60, dt = 1.0 / 60;
            var world = new PetWorld(W, H, ground, 20261105);
            var plans = new[] { (grab: 120, release: 192, dx: 250.0, dy: 300.0, label: "往上抬+往右甩"), (grab: 360, release: 390, dx: -900.0, dy: 320.0, label: "往左狠甩（撞墙）") };
            (int grab, int release, double dx, double dy, string label)? active = null;
            double ax = 0, ay = 0, prevVx = 0, maxLift = 0;
            var prev = world.State;
            var seen = new HashSet<PetState> { world.State };
            var violations = new List<string>();
            bool landed = false, bounced = false;
            for (int step = 0; step <= 600; step++)
            {
                double t = step * dt;
                foreach (var p in plans) if (p.grab == step) { ax = world.X; ay = world.Y + 70; world.BeginGrab(ax, ay); active = p; log.AppendLine($"  t={t:0.00}s [输入] 抓住头 ({ax:0},{ay:0})，{p.label}"); }
                if (active.HasValue && step > active.Value.grab && step < active.Value.release)
                {
                    double u = (double)(step - active.Value.grab) / (active.Value.release - active.Value.grab);
                    world.Drag(ax + active.Value.dx * u, ay + active.Value.dy * (Math.Sin(u * Math.PI) * 0.7 + u * 0.6));
                }
                if (active.HasValue && step == active.Value.release) { world.EndGrab(); log.AppendLine($"  t={t:0.00}s [输入] 松手，抛出速度 ({world.VX:0},{world.VY:0})"); active = null; }
                world.Update(dt);
                if (world.Y < ground - 0.01) violations.Add($"t={t:0.0} 穿地 y={world.Y:0.0}");
                if (world.X < -0.01 || world.X > W + 0.01) violations.Add($"t={t:0.0} 横向出屏 x={world.X:0}");
                if (world.Y > H + 0.01) violations.Add($"t={t:0.0} 纵向出屏 y={world.Y:0}");
                maxLift = Math.Max(maxLift, world.Y - ground);
                if (world.State == PetState.Falling && ((prevVx < -40 && world.VX > 20) || (prevVx > 40 && world.VX < -20))) { bounced = true; log.AppendLine($"  t={t:0.00}s [检查] 撞墙反弹 vx {prevVx:0} → {world.VX:0}"); }
                prevVx = world.VX;
                if (world.State != prev)
                {
                    log.AppendLine($"  t={t:0.00}s {prev.Name()} → {world.State.Name()}  位置=({world.X:0},{world.Y:0})");
                    if (world.State == PetState.Landing) landed = true;
                    prev = world.State; seen.Add(world.State);
                }
            }
            var problems = new List<string>();
            if (violations.Count > 0) problems.Add($"违反不变量：{violations[0]}（共 {violations.Count} 次）");
            if (!seen.Contains(PetState.Grabbed)) problems.Add("没有进入「被拎起」");
            if (!seen.Contains(PetState.Falling)) problems.Add("没有进入「下落」");
            if (!landed) problems.Add("没有落地动作");
            if (!bounced) problems.Add("没有撞墙反弹");
            if (!(world.State == PetState.Idle || world.State == PetState.Walk)) problems.Add($"最后没回到闲逛（{world.State.Name()}）");
            if (maxLift < 80) problems.Add($"没被抬起来（最大离地 {maxLift:0}）");
            if (!jumped) problems.Add("没有自己跳上小窗口");

            // 跳舞 / 睡觉 / 摸头 / 举牌
            var w2 = new PetWorld(1600, 900, 60, 7);
            w2.SoundPlaying = true; for (int i = 0; i < 30; i++) w2.Update(dt);
            if (w2.State != PetState.Dance) problems.Add($"有声音时没跳舞（{w2.State.Name()}）");
            w2.SoundPlaying = false; for (int i = 0; i < 30; i++) w2.Update(dt);
            w2.IdleSeconds = 400; for (int i = 0; i < 400; i++) w2.Update(dt);
            if (w2.State != PetState.Sleep) problems.Add($"5 分钟没动没睡觉（{w2.State.Name()}）");
            w2.IdleSeconds = 0; for (int i = 0; i < 10; i++) w2.Update(dt);
            if (w2.State != PetState.Wake) problems.Add($"动了鼠标没醒（{w2.State.Name()}）");
            for (int i = 0; i < 200; i++) w2.Update(dt);
            for (int i = 0; i < 20; i++) { w2.Pet(0.05); w2.Update(dt); }
            if (w2.State != PetState.Petted) problems.Add($"摸头没反应（{w2.State.Name()}）");
            for (int i = 0; i < 300; i++) w2.Update(dt);
            w2.ShowSign("喝口水吧 💧"); w2.Update(dt);
            if (w2.State != PetState.Sign || w2.SignText == null) problems.Add("没举牌");

            foreach (var p in problems) log.AppendLine("  ✗ " + p);
            log.AppendLine(problems.Count == 0 ? "  状态机：PASS" : "  状态机：FAIL");
            return problems.Count == 0;
        }
    }
}
