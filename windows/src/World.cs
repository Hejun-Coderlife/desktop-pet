// 世界（纯逻辑）+ 姿势：逐行对应 Mac 版 PetWorld.swift / Pose.swift / PetAnimator.swift
// 坐标系：主屏左下角为原点，单位是点（DIP），y 向上
using System;
using System.Collections.Generic;
using System.Linq;

namespace Pip
{
    enum PetState { Idle, Walk, Grabbed, Falling, Landing, Sleep, Wake, Petted, Dance, Sign, Perch }

    static class PetStateNames
    {
        public static string Name(this PetState s)
        {
            switch (s)
            {
                case PetState.Idle: return "发呆";
                case PetState.Walk: return "走路";
                case PetState.Grabbed: return "被拎起";
                case PetState.Falling: return "下落";
                case PetState.Landing: return "落地";
                case PetState.Sleep: return "睡觉";
                case PetState.Wake: return "伸懒腰";
                case PetState.Petted: return "被摸头";
                case PetState.Dance: return "跳舞";
                case PetState.Sign: return "举牌";
                default: return "坐窗口上";
            }
        }
    }

    class SeededRNG
    {
        ulong state;
        public SeededRNG(ulong seed) { unchecked { state = seed * 0x9E3779B97F4A7C15UL; } }
        public ulong Next()
        {
            unchecked
            {
                state += 0x9E3779B97F4A7C15UL;
                ulong z = state;
                z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                return z ^ (z >> 31);
            }
        }
        public double Unit() => (Next() >> 11) * (1.0 / 9007199254740992.0);
        public double Range(double lo, double hi) => lo + Unit() * (hi - lo);
        public bool Chance(double p) => Unit() < p;
    }

    struct Platform
    {
        public long Id; public double X0, X1, Y;
        public Platform(long id, double x0, double x1, double y) { Id = id; X0 = x0; X1 = x1; Y = y; }
        public bool Same(Platform o) => Id == o.Id && X0 == o.X0 && X1 == o.X1 && Y == o.Y;
        public override string ToString() => $"id={Id} x={X0:0}…{X1:0} y={Y:0}";
    }

    class PetWorld
    {
        public const double WalkSpeed = 46, Gravity = 2400, AirDrag = 0.9, WallRestitution = 0.45, CeilingRestitution = 0.3;
        public const double MaxThrowSpeed = 2000, LandingDuration = 0.42, SleepAfter = 300, WakeDuration = 1.6, SignDuration = 10;
        public const double JumpReach = 600;

        public readonly double HalfWidth = 32, CharacterHeight = 92;

        public double Width { get; private set; }
        public double Height { get; private set; }
        public double GroundY { get; private set; }

        public double X, Y;                       // 脚底位置
        public double VX, VY;
        public double Facing { get; private set; } = 1;
        public PetState State { get; private set; } = PetState.Idle;
        public double Time { get; private set; }
        public double StateTime { get; private set; }
        public double WalkPhase { get; private set; }
        public double GrabVX { get; private set; }
        public double GrabVY { get; private set; }
        public double LandingImpact { get; private set; }
        public bool Startled { get; private set; }
        public double Happy { get; private set; }
        public string SignText { get; private set; }
        public Platform? PlatformFront { get; private set; }
        public List<Platform> Platforms { get; private set; } = new List<Platform>();
        public Platform? Standing { get; private set; }
        public bool OnPlatform => Standing.HasValue;

        // 外界输入
        public double IdleSeconds;
        public bool SoundPlaying;
        public bool ClimbEnabled = true;
        public double? AttentionX;

        public double SupportY => Standing?.Y ?? GroundY;
        double SupportMinX => Standing.HasValue ? Math.Max(MinX, Standing.Value.X0 + HalfWidth * 0.6) : MinX;
        double SupportMaxX => Standing.HasValue ? Math.Min(MaxX, Standing.Value.X1 - HalfWidth * 0.6) : MaxX;

        double grabOffX, grabOffY;
        PetState grabbedFrom = PetState.Idle;
        double? dragX, dragY;
        double wanderTimer, wanderDuration = 1.8;
        readonly SeededRNG rng;

        public PetWorld(double width, double height, double groundY, ulong seed = 0x5EED2026)
        {
            Width = width; Height = height; GroundY = groundY;
            rng = new SeededRNG(seed);
            X = width / 2; Y = groundY;
        }

        public double MinX => HalfWidth;
        public double MaxX => Math.Max(HalfWidth * 2, Width - HalfWidth);

        public bool IsMoving => !(State == PetState.Idle || State == PetState.Sleep);

        public void SetGeometry(double width, double height, double groundY)
        {
            Width = width; Height = height; GroundY = groundY;
            X = Math.Min(Math.Max(X, MinX), MaxX);
            if (State == PetState.Grabbed || State == PetState.Falling) Y = Math.Min(Math.Max(Y, groundY), height);
            else Y = SupportY;
        }

        public void Update(double rawDt)
        {
            double dt = Math.Min(Math.Max(rawDt, 0), 0.1);
            if (dt <= 0) return;
            Time += dt; StateTime += dt;
            Happy = Math.Max(0, Happy - dt * 0.35);
            UpdateMoods();
            switch (State)
            {
                case PetState.Idle: case PetState.Walk: case PetState.Perch: UpdateWander(dt); break;
                case PetState.Grabbed: UpdateGrabbed(dt); break;
                case PetState.Falling: UpdateFalling(dt); break;
                case PetState.Landing:
                    Y = SupportY; VX = VY = 0;
                    if (StateTime >= LandingDuration) BeginWander();
                    break;
                case PetState.Sleep: case PetState.Dance: case PetState.Petted:
                    Y = SupportY; VX = VY = 0; break;
                case PetState.Wake:
                    Y = SupportY;
                    if (StateTime >= WakeDuration) BeginWander();
                    break;
                case PetState.Sign:
                    Y = SupportY;
                    if (StateTime >= SignDuration) { SignText = null; BeginWander(); }
                    break;
            }
        }

        void UpdateMoods()
        {
            var calm = State == PetState.Idle || State == PetState.Walk || State == PetState.Perch || State == PetState.Dance || State == PetState.Sleep || State == PetState.Petted;
            if (!calm) return;
            if (State == PetState.Sleep) { if (IdleSeconds < 1) Enter(PetState.Wake); return; }
            if (Happy > 0.45) { if (State != PetState.Petted) Enter(PetState.Petted); return; }
            if (State == PetState.Petted) { if (Happy < 0.12) BeginWander(); return; }
            if (SoundPlaying) { if (State != PetState.Dance) Enter(PetState.Dance); return; }
            if (State == PetState.Dance) { BeginWander(); return; }
            if (IdleSeconds > SleepAfter) Enter(PetState.Sleep);
        }

        void Enter(PetState s) { State = s; StateTime = 0; VX = VY = 0; Y = SupportY; }

        public void Pet(double amount)
        {
            if (State == PetState.Grabbed || State == PetState.Falling) return;
            Happy = Math.Min(1, Happy + amount);
        }

        public void Startle()
        {
            if (State == PetState.Sign) { SignText = null; BeginWander(); return; }
            if (State == PetState.Falling || State == PetState.Grabbed) return;
            if (State == PetState.Sleep) { Enter(PetState.Wake); return; }
            State = PetState.Falling; StateTime = 0; Startled = true;
            VX = 0; VY = 720; Standing = null;
        }

        public void Click()
        {
            if (State != PetState.Grabbed) return;
            dragX = dragY = null; GrabVX = GrabVY = 0;
            switch (grabbedFrom)
            {
                case PetState.Sign: BeginWanderKeepingHeight(); break;
                case PetState.Sleep: State = PetState.Idle; Enter(PetState.Wake); break;
                default: State = PetState.Idle; Startle(); break;
            }
        }

        void BeginWanderKeepingHeight()
        {
            Standing = null;
            foreach (var p in Platforms)
                if (Math.Abs(Y - p.Y) < 2 && X >= p.X0 && X <= p.X1) { Standing = p; break; }
            BeginWander();
        }

        public void ShowSign(string text)
        {
            if (State == PetState.Grabbed || State == PetState.Falling) return;
            SignText = text; Enter(PetState.Sign);
        }

        public void SetPlatform(Platform? p) { PlatformFront = ClimbEnabled ? p : null; }

        public void SetPlatforms(List<Platform> list)
        {
            Platforms = ClimbEnabled ? list : new List<Platform>();
            if (!Standing.HasValue) return;
            var o = Standing.Value;
            int i = Platforms.FindIndex(q => q.Id == o.Id);
            if (i < 0) { DropFromPlatform(); return; }
            var p = Platforms[i];
            if (!p.Same(o))
            {
                if (Math.Abs((p.X1 - p.X0) - (o.X1 - o.X0)) < 2) X += p.X0 - o.X0;
                Standing = p;
                if (!(X >= p.X0 && X <= p.X1)) { DropFromPlatform(); return; }
                if (State != PetState.Grabbed && State != PetState.Falling) Y = p.Y;
            }
        }

        void DropFromPlatform()
        {
            Standing = null;
            if (State == PetState.Grabbed || State == PetState.Falling) return;
            State = PetState.Falling; StateTime = 0; VX = Facing * 60; VY = 0;
        }

        void BeginWander()
        {
            State = PetState.Idle; StateTime = 0; wanderTimer = 0;
            wanderDuration = rng.Range(0.5, 1.2);
            VX = VY = 0; Startled = false; Y = SupportY;
        }

        void ChooseWanderAction()
        {
            wanderTimer = 0; StateTime = 0;
            if (OnPlatform)
            {
                if (rng.Chance(0.12)) { HopDown(); return; }
                if (rng.Chance(0.5)) { State = PetState.Perch; wanderDuration = rng.Range(3, 7); return; }
            }
            else if (AttentionX == null && rng.Chance(0.3))
            {
                var p = NearestReachable();
                if (p.HasValue && JumpUp(p.Value)) return;
            }
            if (rng.Chance(0.58)) { State = PetState.Walk; wanderDuration = rng.Range(0.9, 2.8); }
            else { State = PetState.Idle; wanderDuration = rng.Range(1.2, 3.2); }
            if (rng.Chance(0.7)) Facing = rng.Chance(0.5) ? -1 : 1;
        }

        void UpdateWander(double dt)
        {
            if (AttentionX.HasValue && !OnPlatform)
            {
                double dx = AttentionX.Value - X;
                if (Math.Abs(dx) > 34) { State = PetState.Walk; Facing = dx > 0 ? 1 : -1; wanderTimer = 0; wanderDuration = 0.6; }
                else if (State == PetState.Walk) { State = PetState.Idle; wanderTimer = 0; wanderDuration = 1.5; }
            }
            wanderTimer += dt;
            if (wanderTimer >= wanderDuration)
            {
                ChooseWanderAction();
                if (State == PetState.Falling) return;
            }
            if (State == PetState.Walk)
            {
                double speed = AttentionX.HasValue ? WalkSpeed * 1.25 : WalkSpeed;
                X += Facing * speed * dt;
                WalkPhase += dt * 8.6;
                if (X <= SupportMinX) { X = SupportMinX; Facing = 1; }
                else if (X >= SupportMaxX) { X = SupportMaxX; Facing = -1; }
            }
            Y = SupportY; VX = VY = 0;
        }

        Platform? NearestReachable()
        {
            var all = new List<Platform>(Platforms);
            if (PlatformFront.HasValue) all.Add(PlatformFront.Value);
            Platform? best = null; double bestD = double.MaxValue;
            foreach (var p in all)
            {
                double h = p.Y - GroundY;
                if (!(h > 70 && h < 760 && p.X1 - p.X0 > HalfWidth * 3)) continue;
                double tx = Math.Min(Math.Max(X, p.X0 + HalfWidth * 1.4), p.X1 - HalfWidth * 1.4);
                if (!(Math.Abs(tx - X) < JumpReach)) continue;
                double d = Math.Abs(Math.Min(Math.Max(X, p.X0), p.X1) - X);
                if (d < bestD) { bestD = d; best = p; }
            }
            return best;
        }

        bool JumpUp(Platform p)
        {
            double h = p.Y - GroundY;
            if (!(h > 70 && h < 760 && p.X1 - p.X0 > HalfWidth * 3)) return false;
            double tx = Math.Min(Math.Max(X, p.X0 + HalfWidth * 1.4), p.X1 - HalfWidth * 1.4);
            if (!(Math.Abs(tx - X) < JumpReach)) return false;
            double rise = h + 46;
            double vy = Math.Sqrt(2 * Gravity * rise);
            double tUp = vy / Gravity, tDown = Math.Sqrt(2 * 46 / Gravity);
            double vx = (tx - X) / (tUp + tDown);
            vx /= Math.Max(0.05, 1 - AirDrag * (tUp + tDown) / 2);
            Facing = vx >= 0 ? 1 : -1;
            State = PetState.Falling; StateTime = 0; VX = vx; VY = vy;
            return true;
        }

        void HopDown() { Standing = null; State = PetState.Falling; StateTime = 0; VX = Facing * 160; VY = 380; }

        public void BeginGrab(double px, double py)
        {
            if (State == PetState.Grabbed) return;
            grabbedFrom = State; Standing = null;
            if (State == PetState.Sign) SignText = null;
            State = PetState.Grabbed; StateTime = 0; VX = VY = 0; GrabVX = GrabVY = 0;
            dragX = px; dragY = py;
            grabOffX = X - px; grabOffY = Y - py;
        }

        public void Drag(double px, double py) { if (State == PetState.Grabbed) { dragX = px; dragY = py; } }

        void UpdateGrabbed(double dt)
        {
            if (!dragX.HasValue) return;
            double dx0 = Math.Min(Math.Max(dragX.Value + grabOffX, MinX), MaxX);
            double dy0 = Math.Min(Math.Max(dragY.Value + grabOffY, GroundY), Height - CharacterHeight * 0.6);
            double dx = dx0 - X, dy = dy0 - Y;
            GrabVX = GrabVX * 0.6 + dx / dt * 0.4;
            GrabVY = GrabVY * 0.6 + dy / dt * 0.4;
            X = dx0; Y = dy0;
        }

        public void EndGrab()
        {
            if (State != PetState.Grabbed) return;
            dragX = dragY = null;
            double tvx = GrabVX, tvy = GrabVY, speed = Math.Sqrt(tvx * tvx + tvy * tvy);
            if (speed > MaxThrowSpeed) { double s = MaxThrowSpeed / speed; tvx *= s; tvy *= s; }
            VX = tvx; VY = tvy; GrabVX = GrabVY = 0;
            State = PetState.Falling; StateTime = 0;
        }

        void UpdateFalling(double dt)
        {
            double prevY = Y;
            VY -= Gravity * dt;
            VX *= Math.Max(0, 1 - AirDrag * dt);
            X += VX * dt; Y += VY * dt;
            if (X < MinX) { X = MinX; VX = Math.Abs(VX) * WallRestitution; }
            else if (X > MaxX) { X = MaxX; VX = -Math.Abs(VX) * WallRestitution; }
            double ceiling = Height - 4;
            if (Y > ceiling) { Y = ceiling; VY = -Math.Abs(VY) * CeilingRestitution; }

            var cands = new List<Platform>(Platforms);
            if (PlatformFront.HasValue) cands.Add(PlatformFront.Value);
            Platform? hit = null;
            foreach (var p in cands)
                if (VY <= 0 && prevY >= p.Y - 0.5 && Y <= p.Y && X >= p.X0 + HalfWidth * 0.4 && X <= p.X1 - HalfWidth * 0.4)
                    if (!hit.HasValue || p.Y > hit.Value.Y) hit = p;
            if (hit.HasValue)
            {
                double impact = Math.Abs(VY);
                Standing = hit; Y = hit.Value.Y; VX = VY = 0; Startled = false;
                if (impact > 140) { LandingImpact = Math.Min(1, impact / 1400); State = PetState.Landing; StateTime = 0; }
                else BeginWander();
                return;
            }
            if (Y <= GroundY && VY <= 0)
            {
                Standing = null; Startled = false;
                double impact = Math.Abs(VY);
                Y = GroundY; VX = VY = 0;
                if (impact > 140) { LandingImpact = Math.Min(1, impact / 1400); State = PetState.Landing; StateTime = 0; }
                else BeginWander();
            }
        }

        /// 渲染测试用：直接摆成某个状态
        public void Preview(PetState s, double time, double fx, double fy, double walkPhase = 0, double stateTime = 0,
                            double vx = 0, double vy = 0, string sign = null, bool startled = false, double facing = 1)
        {
            State = s; SignText = sign; Startled = startled; Facing = facing; Time = time; WalkPhase = walkPhase;
            StateTime = stateTime; VX = vx; VY = vy; X = fx; Y = fy;
        }
    }

    class Pose
    {
        public double FeetX, FeetY, Facing = 1, SquashY = 1, Bob, BodyLean, BodyYaw, HeadPitch, HeadYaw, HeadTilt;
        public double ArmLeft, ArmRight, LegLeft, LegRight, LegSideLeft, LegSideRight, LiftLeft, LiftRight;
        public double Blink, EyeScale = 1, HappyEyes, Blush = 1, Zzz = -1;
        public string Sign;
    }

    static class PetAnimator
    {
        public const double SleepLean = 1.48, SleepLift = 30;

        public static Pose PoseFor(PetWorld w)
        {
            var p = new Pose { FeetX = w.X, FeetY = w.Y, Facing = w.Facing };
            double t = w.Time;
            switch (w.State)
            {
                case PetState.Idle:
                    {
                        double br = Math.Sin(t * 1.7);
                        p.SquashY = 1 + br * 0.012; p.Bob = br * 0.9;
                        p.HeadTilt = Math.Sin(t * 0.6) * 0.05; p.HeadYaw = Math.Sin(t * 0.37) * 0.22;
                        p.ArmLeft = 0.06 + br * 0.03; p.ArmRight = -0.06 - br * 0.03;
                        p.Blink = BlinkAt(t);
                        break;
                    }
                case PetState.Walk:
                    {
                        double s = Math.Sin(w.WalkPhase), s2 = Math.Sin(w.WalkPhase * 2);
                        p.BodyYaw = 0.42;
                        p.LegLeft = s * 0.6; p.LegRight = -s * 0.6;
                        p.LiftLeft = Math.Max(0, s) * 3.2; p.LiftRight = Math.Max(0, -s) * 3.2;
                        p.ArmLeft = 0.15 - s * 0.45; p.ArmRight = -0.15 + s * 0.45;
                        p.Bob = Math.Abs(s2) * 2.6; p.BodyLean = 0.05 + s * 0.14;
                        p.HeadTilt = -s * 0.06; p.SquashY = 1 - Math.Abs(s2) * 0.035;
                        p.Blink = BlinkAt(t);
                        break;
                    }
                case PetState.Grabbed:
                    {
                        double flail = Math.Sin(t * 13), kL = Math.Sin(t * 9.5), kR = Math.Sin(t * 9.5 + 2.2);
                        p.ArmLeft = 2.35 + flail * 0.22; p.ArmRight = 2.35 - flail * 0.22;
                        p.LegSideLeft = 0.22 + kL * 0.32; p.LegSideRight = 0.22 + kR * 0.32;
                        p.LegLeft = kR * 0.25; p.LegRight = kL * 0.25;
                        p.HeadTilt = Math.Sin(t * 4.2) * 0.08; p.HeadYaw = Math.Sin(t * 2.3) * 0.1;
                        p.BodyLean = Clamp(-w.GrabVX * 0.00025, -0.28, 0.28) + Math.Sin(t * 2.6) * 0.06;
                        p.SquashY = 1.12; p.Blink = 0.15;
                        break;
                    }
                case PetState.Falling when w.Startled:
                    p.ArmLeft = 2.0; p.ArmRight = 2.0; p.EyeScale = 1.35; p.SquashY = 1.06;
                    p.LegSideLeft = 0.25; p.LegSideRight = 0.25;
                    break;
                case PetState.Falling:
                    {
                        double speed = Math.Sqrt(w.VX * w.VX + w.VY * w.VY);
                        p.SquashY = 1 + Math.Min(0.12, speed / 12000);
                        p.ArmLeft = 1.5 + Math.Sin(t * 9) * 0.12; p.ArmRight = 1.5 - Math.Sin(t * 9) * 0.12;
                        p.LegLeft = 0.35; p.LegRight = -0.35;
                        p.HeadPitch = Clamp(-w.VY * 0.00012, -0.15, 0.15); p.HeadTilt = 0.05;
                        break;
                    }
                case PetState.Landing:
                    {
                        double u = Math.Min(1, w.StateTime / PetWorld.LandingDuration), sq;
                        if (u < 0.22) sq = Lerp(1.0, 0.75, Ease(u / 0.22));
                        else if (u < 0.5) sq = Lerp(0.75, 1.09, Ease((u - 0.22) / 0.28));
                        else if (u < 0.72) sq = Lerp(1.09, 0.96, Ease((u - 0.5) / 0.22));
                        else sq = Lerp(0.96, 1.0, Ease((u - 0.72) / 0.28));
                        p.SquashY = sq;
                        p.ArmLeft = 0.6 * (1 - u); p.ArmRight = 0.6 * (1 - u);
                        p.LegLeft = 0.2 * (1 - u); p.LegRight = -0.2 * (1 - u);
                        break;
                    }
                case PetState.Sleep:
                    {
                        double br = Math.Sin(t * 1.4);
                        p.BodyLean = SleepLean; p.Bob = SleepLift + br * 0.6; p.SquashY = 0.97 + br * 0.012;
                        p.ArmLeft = 0.15; p.ArmRight = 0.15; p.LegLeft = 0.15; p.LegRight = -0.1;
                        p.Blink = 1; p.Zzz = t;
                        break;
                    }
                case PetState.Wake:
                    {
                        double u = Math.Min(1, w.StateTime / PetWorld.WakeDuration);
                        double rise = Ease(Math.Min(1, u / 0.35));
                        p.BodyLean = SleepLean * (1 - rise); p.Bob = SleepLift * (1 - rise);
                        double v = Math.Max(0, (u - 0.35) / 0.65), reach = Math.Sin(v * Math.PI);
                        p.ArmLeft = 0.3 + reach * 2.4; p.ArmRight = 0.3 + reach * 2.4;
                        p.SquashY = 0.9 + reach * 0.2; p.HeadPitch = -reach * 0.15;
                        p.Blink = Math.Max(0, 1 - u * 1.6) * 0.8; p.HappyEyes = reach * 0.6;
                        break;
                    }
                case PetState.Petted:
                    {
                        double sway = Math.Sin(t * 3.2);
                        p.HappyEyes = 1; p.Blush = 1.9; p.BodyLean = sway * 0.1; p.HeadTilt = sway * 0.12 + 0.05;
                        p.SquashY = 0.97 + Math.Abs(Math.Sin(t * 3.2)) * 0.03;
                        p.ArmLeft = 0.25 + sway * 0.1; p.ArmRight = 0.25 - sway * 0.1;
                        break;
                    }
                case PetState.Dance:
                    {
                        double beat = t * (112.0 / 60.0) * 2 * Math.PI, b = Math.Sin(beat), half = Math.Sin(beat / 2);
                        p.Bob = Math.Abs(b) * 3.2; p.SquashY = 1 - Math.Abs(b) * 0.05;
                        p.BodyLean = half * 0.16; p.HeadTilt = -half * 0.14;
                        p.ArmLeft = 0.4 + Math.Max(0, half) * 1.9; p.ArmRight = 0.4 + Math.Max(0, -half) * 1.9;
                        p.LiftLeft = Math.Max(0, half) * 2.4; p.LiftRight = Math.Max(0, -half) * 2.4;
                        p.HappyEyes = 0.8; p.Blush = 1.3;
                        break;
                    }
                case PetState.Sign:
                    {
                        double sway = Math.Sin(t * 2.4);
                        p.ArmLeft = 2.55; p.ArmRight = 2.55; p.BodyLean = sway * 0.05; p.HeadTilt = sway * 0.06;
                        p.Sign = w.SignText; p.Blink = BlinkAt(t);
                        break;
                    }
                case PetState.Perch:
                    {
                        double swing = Math.Sin(t * 3.0);
                        p.SquashY = 0.92; p.Bob = -11;
                        p.LegLeft = 0.25 + swing * 0.45; p.LegRight = 0.25 - swing * 0.45;
                        p.ArmLeft = 0.2; p.ArmRight = 0.2;
                        p.HeadTilt = Math.Sin(t * 0.8) * 0.06; p.HeadYaw = Math.Sin(t * 0.5) * 0.2;
                        p.Blink = BlinkAt(t);
                        break;
                    }
            }
            return p;
        }

        static double BlinkAt(double t)
        {
            double period = 4.7, window = 0.16, phase = t % period;
            if (!(phase > period - window)) return 0;
            return Math.Sin((phase - (period - window)) / window * Math.PI);
        }
        static double Ease(double x) { double t = Math.Min(Math.Max(x, 0), 1); return t * t * (3 - 2 * t); }
        static double Lerp(double a, double b, double t) => a + (b - a) * t;
        static double Clamp(double v, double lo, double hi) => Math.Min(Math.Max(v, lo), hi);
    }
}
