// 渲染器：把节点树画进离屏帧缓冲（4×MSAA，至少 2 倍超采样），读回预乘 alpha 的 BGRA 像素给分层窗口用。
// 光照照抄 Mac 版 SceneFactory：环境光 540 + 主光 620 + 冷补光 280 + 轮廓光 240（SceneKit 1000 = 1.0），线性空间计算。
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Pip
{
    class Renderer
    {
        const string VS = @"#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNor;
layout(location=2) in vec2 aUV;
uniform mat4 uModel;
uniform mat4 uViewProj;
uniform mat3 uNormalMat;
uniform int uMode;
uniform float uFurH;
uniform float uFurLen;
uniform vec4 uFaceHole;
out vec3 vNor;
out vec2 vUV;
out vec3 vModelPos;
void main() {
    vec3 p = aPos;
    vModelPos = aPos;
    if (uMode == 3) {
        // 脸四周一圈毛更长，隆起成兜帽的帽沿（Fur.swift geometryModifier）
        float boost = 0.0;
        if (uFaceHole.z > 0.0 && aPos.z > 0.0) {
            vec2 fd = abs((aPos.xy - uFaceHole.xy) / uFaceHole.zw);
            float fr = pow(pow(fd.x, 2.35) + pow(fd.y, 2.35), 1.0 / 2.35);
            boost = 1.0 - smoothstep(1.0, 1.5, fr);
        }
        float off = uFurH * uFurLen * (1.0 + boost);
        p += aNor * off;
        p.y -= uFurH * uFurH * uFurLen * 0.12;
    }
    vNor = normalize(uNormalMat * aNor);
    vUV = aUV;
    gl_Position = uViewProj * uModel * vec4(p, 1.0);
}";

        const string FS = @"#version 330 core
in vec3 vNor;
in vec2 vUV;
in vec3 vModelPos;
out vec4 outColor;
uniform int uMode;            // 0 lambert, 1 blinn, 2 constant, 3 fur
uniform vec3 uColor;          // sRGB
uniform float uAlpha;
uniform float uOpacity;
uniform int uUseTex;
uniform sampler2D uTex;
uniform vec2 uTile;
uniform vec3 uAmbient;
uniform vec3 uLightDir[3];
uniform vec3 uLightCol[3];
uniform float uSpec;
uniform float uFurH;
uniform vec3 uFurRoot;
uniform vec3 uFurTip;
uniform vec3 uFurRim;
uniform vec4 uFaceHole;
uniform int uBackFacing;
uniform int uFurLin;
uniform int uStrandLin;
uniform float uLodBias;

vec3 toLin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 toSrgb(vec3 c) { c = clamp(c, 0.0, 1.0); return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

vec3 diffuseLight(vec3 n) {
    vec3 l = uAmbient;
    for (int i = 0; i < 3; i++) l += uLightCol[i] * max(0.0, dot(n, uLightDir[i]));
    return l;
}

void main() {
    vec3 n = normalize(vNor);
    if (!gl_FrontFacing) n = -n;
    vec3 v = vec3(0.0, 0.0, 1.0);
    if (uMode == 3) {
        if (uFurH > 0.0 && uFaceHole.z > 0.0 && vModelPos.z > 0.0) {
            vec2 d = abs((vModelPos.xy - uFaceHole.xy) / uFaceHole.zw);
            float r = pow(pow(d.x, 2.35) + pow(d.y, 2.35), 1.0 / 2.35);
            if (r < 1.0) discard;
        }
        float strand = texture(uTex, vUV * uTile, uLodBias).r;
        if (uStrandLin == 1) strand = toLin(vec3(strand)).r;
        if (uFurH > 0.0 && strand < uFurH) discard;
        vec3 root = uFurLin == 1 ? toLin(uFurRoot) : uFurRoot;
        vec3 tip = uFurLin == 1 ? toLin(uFurTip) : uFurTip;
        vec3 rimc = uFurLin == 1 ? toLin(uFurRim) : uFurRim;
        vec3 c = mix(root, tip, uFurH * 0.9 + strand * 0.04);
        c *= mix(0.9, 1.0, sqrt(uFurH));
        float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 2.2);
        vec3 lit = c * diffuseLight(n) + rimc * rim * (0.05 + 0.10 * uFurH);
        outColor = vec4(toSrgb(lit), 1.0) * uOpacity;
        return;
    }
    vec4 base = vec4(toLin(uColor), uAlpha);
    if (uUseTex == 1) {
        vec4 t = texture(uTex, vUV);
        vec3 straight = t.a > 0.0001 ? t.rgb / t.a : vec3(0.0);
        base = vec4(toLin(straight) * toLin(uColor), t.a * uAlpha);
    }
    vec3 lit;
    if (uMode == 2) {
        lit = base.rgb;
    } else {
        lit = base.rgb * diffuseLight(n);
        if (uMode == 1) {
            for (int i = 0; i < 3; i++) {
                vec3 h = normalize(uLightDir[i] + v);
                lit += uLightCol[i] * uSpec * pow(max(0.0, dot(n, h)), 48.0);
            }
        }
    }
    float a = base.a * uOpacity;
    outColor = vec4(toSrgb(lit) * a, a);
}";

        uint prog;
        readonly Dictionary<string, int> loc = new Dictionary<string, int>();
        uint msFbo, msColor, msDepth, ssFbo, ssColor, outFbo, outColor;
        int fbW, fbH, ssW, ssH, outW, outH;
        public string Info { get; private set; }
        /// 驱动是 CPU 软件渲染（llvmpipe / 微软 GDI 通用实现等虚拟机常见情况）
        public bool Software { get; private set; }
        /// 绒毛颜色 / 毛高贴图是否按 sRGB 解码：和 Mac 真机屏幕截图逐点对色定下来的（绒毛色不解码、毛高贴图解码）
        public static bool FurLinear = Environment.GetEnvironmentVariable("PIP_FURLIN") == "1";
        public static float LodBias = float.TryParse(Environment.GetEnvironmentVariable("PIP_LODBIAS"), out var lb) ? lb : 0;
        public static bool StrandLinear = Environment.GetEnvironmentVariable("PIP_STRANDLIN") != "0";
        float[] lightDir = new float[9], lightCol = new float[9];
        V3 ambient;

        public static V3 Lin(V3 c)
        {
            float f(float x) => x <= 0.04045f ? x / 12.92f : F.Pow((x + 0.055f) / 1.055f, 2.4f);
            return new V3(f(c.X), f(c.Y), f(c.Z));
        }

        public void Init()
        {
            Info = $"{GL.Str(GL.VENDOR)} | {GL.Str(GL.RENDERER)} | GL {GL.Str(GL.VERSION)}";
            var rn = (GL.Str(GL.RENDERER) ?? "").ToLowerInvariant();
            Software = rn.Contains("llvmpipe") || rn.Contains("softpipe") || rn.Contains("gdi generic") || rn.Contains("basic render");
            prog = Link(Compile(GL.VERTEX_SHADER, VS), Compile(GL.FRAGMENT_SHADER, FS));
            ambient = Lin(new V3(1.0f, 0.97f, 0.95f)) * 0.54f;
            void Light(int i, V3 srgb, float intensity, V3 euler)
            {
                var d = M4.Euler(euler).Point(new V3(0, 0, 1)).Normalized;   // 光朝 -Z 照，指向光源的方向 = 旋转后的 +Z
                var c = Lin(srgb) * intensity;
                lightDir[i * 3] = d.X; lightDir[i * 3 + 1] = d.Y; lightDir[i * 3 + 2] = d.Z;
                lightCol[i * 3] = c.X; lightCol[i * 3 + 1] = c.Y; lightCol[i * 3 + 2] = c.Z;
            }
            Light(0, new V3(1.0f, 0.97f, 0.94f), 0.62f, new V3(-0.55f, -0.5f, 0));
            Light(1, new V3(0.82f, 0.88f, 1.0f), 0.28f, new V3(0.35f, 0.9f, 0));
            // 轮廓光 240 和补光并在一起：Mac 版有 4 盏灯，这里第 3 槽放轮廓光、主光吸收不了的就叠进补光
            var rimD = M4.Euler(new V3(-0.2f, 2.5f, 0)).Point(new V3(0, 0, 1)).Normalized;
            var rimC = Lin(new V3(1, 1, 1)) * 0.24f;
            lightDir[6] = rimD.X; lightDir[7] = rimD.Y; lightDir[8] = rimD.Z;
            lightCol[6] = rimC.X; lightCol[7] = rimC.Y; lightCol[8] = rimC.Z;
        }

        // 着色器源码交给驱动前清成纯 ASCII：GL.ShaderSource 按系统 ANSI 代码页编码（中文 Windows = GBK），
        // GBK 有些汉字第二个字节是 0x5C（反斜杠），落在行末会被当成续行符，把下一行代码并进注释，语法全乱。
        // 先删 /* */ 块注释和 // 行注释，再删掉剩下所有 >127 的字符。
        static string ToAsciiShader(string src)
        {
            src = System.Text.RegularExpressions.Regex.Replace(src, @"/\*.*?\*/", "", System.Text.RegularExpressions.RegexOptions.Singleline);
            src = System.Text.RegularExpressions.Regex.Replace(src, @"//[^\r\n]*", "");
            var sb = new System.Text.StringBuilder(src.Length);
            foreach (char c in src) if (c <= 127) sb.Append(c);
            return sb.ToString();
        }

        static uint Compile(uint type, string src)
        {
            src = ToAsciiShader(src);
            uint s = GL.CreateShader(type);
            GL.ShaderSource(s, 1, new[] { src }, IntPtr.Zero);
            GL.CompileShader(s);
            GL.GetShaderiv(s, GL.COMPILE_STATUS, out int ok);
            if (ok == 0)
            {
                var log = new byte[4096]; GL.GetShaderInfoLog(s, log.Length, out int len, log);
                string msg = System.Text.Encoding.ASCII.GetString(log, 0, Math.Max(0, len));
                WriteShaderError(type, msg, src);
                throw new Exception("着色器编译失败：" + msg);
            }
            return s;
        }

        // 编译失败时把清理后的源码带行号写进 %LOCALAPPDATA%\Pip\shader-error.txt，行号跟驱动报错里的对得上
        static void WriteShaderError(uint type, string log, string src)
        {
            try
            {
                string dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Pip");
                System.IO.Directory.CreateDirectory(dir);
                var sb = new System.Text.StringBuilder();
                sb.AppendLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + (type == GL.VERTEX_SHADER ? "顶点着色器" : "片元着色器") + " 编译失败");
                sb.AppendLine(log.TrimEnd('\0', '\r', '\n'));
                sb.AppendLine();
                string[] lines = src.Replace("\r\n", "\n").Split('\n');
                for (int i = 0; i < lines.Length; i++) sb.AppendLine((i + 1).ToString().PadLeft(4) + ": " + lines[i]);
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "shader-error.txt"), sb.ToString(), new System.Text.UTF8Encoding(false));
            }
            catch { }
        }

        static uint Link(uint vs, uint fs)
        {
            uint p = GL.CreateProgram();
            GL.AttachShader(p, vs); GL.AttachShader(p, fs);
            GL.BindAttribLocation(p, 0, "aPos"); GL.BindAttribLocation(p, 1, "aNor"); GL.BindAttribLocation(p, 2, "aUV");
            GL.LinkProgram(p);
            GL.GetProgramiv(p, GL.LINK_STATUS, out int ok);
            if (ok == 0)
            {
                var log = new byte[4096]; GL.GetProgramInfoLog(p, log.Length, out int len, log);
                throw new Exception("着色器链接失败：" + System.Text.Encoding.ASCII.GetString(log, 0, Math.Max(0, len)));
            }
            return p;
        }

        int U(string name)
        {
            if (!loc.TryGetValue(name, out int l)) { l = GL.GetUniformLocation(prog, name); loc[name] = l; }
            return l;
        }

        static uint RB(uint fmt, int w, int h, int samples)
        {
            GL.GenRenderbuffers(1, out uint rb);
            GL.BindRenderbuffer(GL.RENDERBUFFER, rb);
            if (samples > 0) GL.RenderbufferStorageMultisample(GL.RENDERBUFFER, samples, fmt, w, h);
            else GL.RenderbufferStorage(GL.RENDERBUFFER, fmt, w, h);
            return rb;
        }

        void EnsureTargets(int w, int h, int ssScale)
        {
            int sw = w * ssScale, sh = h * ssScale;
            if (w == outW && h == outH && sw == ssW) return;
            foreach (var f in new[] { msFbo, ssFbo, outFbo }) if (f != 0) { uint x = f; GL.DeleteFramebuffers(1, ref x); }
            foreach (var r in new[] { msColor, msDepth, ssColor, outColor }) if (r != 0) { uint x = r; GL.DeleteRenderbuffers(1, ref x); }
            outW = w; outH = h; ssW = sw; ssH = sh; fbW = sw; fbH = sh;

            GL.GenFramebuffers(1, out msFbo); GL.BindFramebuffer(GL.FRAMEBUFFER, msFbo);
            msColor = RB(GL.RGBA8, sw, sh, 4); GL.FramebufferRenderbuffer(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.RENDERBUFFER, msColor);
            msDepth = RB(GL.DEPTH_COMPONENT24, sw, sh, 4); GL.FramebufferRenderbuffer(GL.FRAMEBUFFER, GL.DEPTH_ATTACHMENT, GL.RENDERBUFFER, msDepth);
            Check("msaa");
            GL.GenFramebuffers(1, out ssFbo); GL.BindFramebuffer(GL.FRAMEBUFFER, ssFbo);
            ssColor = RB(GL.RGBA8, sw, sh, 0); GL.FramebufferRenderbuffer(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.RENDERBUFFER, ssColor);
            Check("resolve");
            GL.GenFramebuffers(1, out outFbo); GL.BindFramebuffer(GL.FRAMEBUFFER, outFbo);
            outColor = RB(GL.RGBA8, w, h, 0); GL.FramebufferRenderbuffer(GL.FRAMEBUFFER, GL.COLOR_ATTACHMENT0, GL.RENDERBUFFER, outColor);
            Check("output");
        }

        static void Check(string what)
        {
            uint st = GL.CheckFramebufferStatus(GL.FRAMEBUFFER);
            if (st != GL.FRAMEBUFFER_COMPLETE) throw new Exception($"帧缓冲（{what}）不完整：0x{st:X}");
        }

        struct Item { public Node N; public M4 W; public float Op; public int Order; public bool Transparent; public float Z; public int Seq; }

        void Collect(Node n, M4 parent, float op, List<Item> items)
        {
            if (n.Hidden) return;
            var w = parent * n.Local;
            float o = op * n.Opacity;
            if (o <= 0.001f) return;
            if (n.Mesh != null && n.Mat != null)
            {
                bool tr = n.Mat.Blend || o < 0.999f || n.Mat.Alpha < 0.999f;
                items.Add(new Item { N = n, W = w, Op = o, Order = n.Order, Transparent = tr, Z = w[2, 3], Seq = items.Count });
            }
            foreach (var c in n.Children) Collect(c, w, o, items);
        }

        /// 画一帧：取景框 (ox, oy) 起、宽高 w×h 点，像素缩放 scale；结果写到 dest（BGRA，自下而上，预乘 alpha）
        public void Render(IList<Node> roots, float ox, float oy, float wPts, float hPts, float scale, IntPtr dest)
        {
            int outWpx = Math.Max(1, (int)Math.Round(wPts * scale)), outHpx = Math.Max(1, (int)Math.Round(hPts * scale));
            int ss = scale >= 1.99f || Software ? 1 : 2;   // 没显卡（软件渲染）时不超采样，省 3/4 的活   // 低分屏也按 2 倍渲染再缩小：绒毛的 mipmap 层级和 Mac 视网膜屏一致
            EnsureTargets(outWpx, outHpx, ss);

            GL.BindFramebuffer(GL.FRAMEBUFFER, msFbo);
            GL.Viewport(0, 0, fbW, fbH);
            GL.ClearColor(0, 0, 0, 0);
            GL.DepthMask(1);
            GL.Clear(GL.COLOR_BUFFER_BIT | GL.DEPTH_BUFFER_BIT);
            GL.Enable(GL.DEPTH_TEST); GL.DepthFunc(GL.LEQUAL);
            GL.Enable(GL.BLEND); GL.BlendFuncSeparate(GL.ONE, GL.ONE_MINUS_SRC_ALPHA, GL.ONE, GL.ONE_MINUS_SRC_ALPHA);
            GL.FrontFace(GL.CCW); GL.CullFace(GL.BACK);
            GL.UseProgram(prog);

            // 相机：z=1200 往 -Z 看，正交，取景框就是窗口
            var proj = M4.Ortho(ox, ox + wPts, oy, oy + hPts, 1, 4000) * M4.Translate(new V3(0, 0, -1200));
            GL.UniformMatrix4fv(U("uViewProj"), 1, 0, proj.m);
            GL.Uniform3f(U("uAmbient"), ambient.X, ambient.Y, ambient.Z);
            GL.Uniform3fv(U("uLightDir"), 3, lightDir);
            GL.Uniform3fv(U("uLightCol"), 3, lightCol);
            GL.Uniform1i(U("uTex"), 0);
            GL.Uniform1i(U("uFurLin"), FurLinear ? 1 : 0);
            GL.Uniform1i(U("uStrandLin"), StrandLinear ? 1 : 0);
            GL.Uniform1f(U("uLodBias"), LodBias);

            var items = new List<Item>();
            foreach (var r in roots) Collect(r, M4.Identity(), 1, items);
            // SceneKit：先按 renderingOrder；同一顺序里不透明的先画，透明的从远到近
            items.Sort((a, b) =>
            {
                if (a.Order != b.Order) return a.Order.CompareTo(b.Order);
                if (a.Transparent != b.Transparent) return a.Transparent ? 1 : -1;
                if (a.Transparent && a.Z != b.Z) return a.Z.CompareTo(b.Z);
                return a.Seq.CompareTo(b.Seq);
            });
            foreach (var it in items) Draw(it);

            // MSAA 解析 → （需要时）缩小到窗口像素
            GL.BindFramebuffer(GL.READ_FRAMEBUFFER, msFbo); GL.BindFramebuffer(GL.DRAW_FRAMEBUFFER, ssFbo);
            GL.BlitFramebuffer(0, 0, fbW, fbH, 0, 0, fbW, fbH, GL.COLOR_BUFFER_BIT, GL.NEAREST);
            GL.BindFramebuffer(GL.READ_FRAMEBUFFER, ssFbo); GL.BindFramebuffer(GL.DRAW_FRAMEBUFFER, outFbo);
            GL.BlitFramebuffer(0, 0, fbW, fbH, 0, 0, outW, outH, GL.COLOR_BUFFER_BIT, (uint)GL.LINEAR);
            GL.BindFramebuffer(GL.FRAMEBUFFER, outFbo);
            GL.PixelStorei(GL.PACK_ALIGNMENT, 4);
            GL.ReadPixels(0, 0, outW, outH, GL.BGRA, GL.UNSIGNED_BYTE, dest);
        }

        public int OutWidth => outW;
        public int OutHeight => outH;

        void Draw(Item it)
        {
            var m = it.N.Mat;
            Upload(it.N.Mesh);
            if (m.DoubleSided || m.Model == Lighting.Constant) GL.Disable(GL.CULL_FACE); else GL.Enable(GL.CULL_FACE);
            GL.DepthMask((byte)(m.WritesDepth && !m.Blend ? 1 : 0));
            if (m.ReadsDepth) GL.Enable(GL.DEPTH_TEST); else GL.Disable(GL.DEPTH_TEST);

            GL.UniformMatrix4fv(U("uModel"), 1, 0, it.W.m);
            GL.UniformMatrix3fv(U("uNormalMat"), 1, 0, it.W.NormalMatrix());
            int mode = m.Model == Lighting.Lambert ? 0 : m.Model == Lighting.Blinn ? 1 : m.Model == Lighting.Constant ? 2 : 3;
            GL.Uniform1i(U("uMode"), mode);
            GL.Uniform3f(U("uColor"), m.Color.X, m.Color.Y, m.Color.Z);
            GL.Uniform1f(U("uAlpha"), m.Alpha);
            GL.Uniform1f(U("uOpacity"), it.Op);
            GL.Uniform1f(U("uSpec"), m.Specular);
            GL.Uniform1f(U("uFurH"), m.FurH);
            GL.Uniform1f(U("uFurLen"), m.FurLen);
            GL.Uniform4f(U("uFaceHole"), m.FaceHole[0], m.FaceHole[1], m.FaceHole[2], m.FaceHole[3]);
            GL.Uniform3f(U("uFurRoot"), m.FurRoot.X, m.FurRoot.Y, m.FurRoot.Z);
            GL.Uniform3f(U("uFurTip"), m.FurTip.X, m.FurTip.Y, m.FurTip.Z);
            GL.Uniform3f(U("uFurRim"), m.FurRim.X, m.FurRim.Y, m.FurRim.Z);
            GL.Uniform2f(U("uTile"), m.TileU, m.TileV);
            if (m.Tex != null)
            {
                UploadTex(m.Tex);
                GL.ActiveTexture(GL.TEXTURE0);
                GL.BindTexture(GL.TEXTURE_2D, (uint)m.Tex.GpuHandle);
                GL.Uniform1i(U("uUseTex"), mode == 3 ? 0 : 1);
            }
            else GL.Uniform1i(U("uUseTex"), 0);

            var h = (uint[])it.N.Mesh.GpuHandle;
            GL.BindVertexArray(h[0]);
            GL.DrawElements(GL.TRIANGLES, it.N.Mesh.Idx.Length, GL.UNSIGNED_INT, IntPtr.Zero);
        }

        static void Buffer(uint target, Array data, int bytes)
        {
            var hnd = GCHandle.Alloc(data, GCHandleType.Pinned);
            try { GL.BufferData(target, (IntPtr)bytes, hnd.AddrOfPinnedObject(), GL.STATIC_DRAW); }
            finally { hnd.Free(); }
        }

        static void Upload(Mesh mesh)
        {
            if (mesh.GpuHandle != null) return;
            GL.GenVertexArrays(1, out uint vao); GL.BindVertexArray(vao);
            uint[] bufs = new uint[4]; bufs[0] = vao;
            int i = 1;
            foreach (var (data, size) in new[] { (mesh.Pos, 3), (mesh.Nor, 3), (mesh.UV, 2) })
            {
                GL.GenBuffers(1, out uint b); bufs[i] = b;
                GL.BindBuffer(GL.ARRAY_BUFFER, b);
                Buffer(GL.ARRAY_BUFFER, data, data.Length * 4);
                GL.EnableVertexAttribArray((uint)(i - 1));
                GL.VertexAttribPointer((uint)(i - 1), size, GL.FLOAT, 0, size * 4, IntPtr.Zero);
                i++;
            }
            GL.GenBuffers(1, out uint ib);
            GL.BindBuffer(GL.ELEMENT_ARRAY_BUFFER, ib);
            Buffer(GL.ELEMENT_ARRAY_BUFFER, mesh.Idx, mesh.Idx.Length * 4);
            GL.BindVertexArray(0);
            mesh.GpuHandle = bufs;
        }

        static void UploadTex(Texture t)
        {
            if (t.GpuHandle != null && !t.Dirty) return;
            if (t.GpuHandle == null) { GL.GenTextures(1, out uint id); t.GpuHandle = id; }
            GL.BindTexture(GL.TEXTURE_2D, (uint)t.GpuHandle);
            GL.PixelStorei(GL.UNPACK_ALIGNMENT, 1);
            var hnd = GCHandle.Alloc(t.Rgba, GCHandleType.Pinned);
            try { GL.TexImage2D(GL.TEXTURE_2D, 0, (int)GL.RGBA8, t.W, t.H, 0, GL.RGBA, GL.UNSIGNED_BYTE, hnd.AddrOfPinnedObject()); }
            finally { hnd.Free(); }
            int wrap = t.Repeat ? GL.REPEAT : GL.CLAMP_TO_EDGE;
            GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_S, wrap);
            GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_WRAP_T, wrap);
            GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MAG_FILTER, GL.LINEAR);
            // 贴图都开 mipmap：文字、腮红缩到很小时也不闪
            GL.GenerateMipmap(GL.TEXTURE_2D);
            GL.TexParameteri(GL.TEXTURE_2D, GL.TEXTURE_MIN_FILTER, GL.LINEAR_MIPMAP_LINEAR);
            t.Dirty = false;
        }
    }
}
