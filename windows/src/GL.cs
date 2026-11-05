// OpenGL 3.3 函数表。Windows：wglGetProcAddress（1.1 的老函数从 opengl32.dll 取）；Mac 渲染测试：dlsym
// 函数签名按 OpenGL 规范写；新增函数在这里加一行 delegate + Load 一行
using System;
using System.Runtime.InteropServices;

namespace Pip
{
    static class GL
    {

        public const uint COLOR_BUFFER_BIT = 0x4000, DEPTH_BUFFER_BIT = 0x100;
        public const uint DEPTH_TEST = 0x0B71, BLEND = 0x0BE2, CULL_FACE = 0x0B44, MULTISAMPLE = 0x809D;
        public const uint ONE = 1, ZERO = 0, ONE_MINUS_SRC_ALPHA = 0x0303, SRC_ALPHA = 0x0302;
        public const uint LEQUAL = 0x0203, LESS = 0x0201, BACK = 0x0405, CCW = 0x0901;
        public const uint TEXTURE_2D = 0x0DE1, TEXTURE0 = 0x84C0, RGBA = 0x1908, BGRA = 0x80E1, RGBA8 = 0x8058, UNSIGNED_BYTE = 0x1401;
        public const uint TEXTURE_MIN_FILTER = 0x2801, TEXTURE_MAG_FILTER = 0x2800, TEXTURE_WRAP_S = 0x2802, TEXTURE_WRAP_T = 0x2803;
        public const int LINEAR = 0x2601, LINEAR_MIPMAP_LINEAR = 0x2703, REPEAT = 0x2901, CLAMP_TO_EDGE = 0x812F;
        public const uint ARRAY_BUFFER = 0x8892, ELEMENT_ARRAY_BUFFER = 0x8893, STATIC_DRAW = 0x88E4, FLOAT = 0x1406, UNSIGNED_INT = 0x1405, TRIANGLES = 4;
        public const uint VERTEX_SHADER = 0x8B31, FRAGMENT_SHADER = 0x8B30, COMPILE_STATUS = 0x8B81, LINK_STATUS = 0x8B82;
        public const uint FRAMEBUFFER = 0x8D40, READ_FRAMEBUFFER = 0x8CA8, DRAW_FRAMEBUFFER = 0x8CA9, RENDERBUFFER = 0x8D41;
        public const uint COLOR_ATTACHMENT0 = 0x8CE0, DEPTH_ATTACHMENT = 0x8D00, DEPTH_COMPONENT24 = 0x81A6, FRAMEBUFFER_COMPLETE = 0x8CD5;
        public const uint PACK_ALIGNMENT = 0x0D05, UNPACK_ALIGNMENT = 0x0CF5, NEAREST = 0x2600;
        public const uint VERSION = 0x1F02, RENDERER = 0x1F01, VENDOR = 0x1F00, SHADING_LANGUAGE_VERSION = 0x8B8C;

        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DViewport(int x, int y, int w, int h);
        public static DViewport Viewport;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DClearColor(float r, float g, float b, float a);
        public static DClearColor ClearColor;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DClear(uint mask);
        public static DClear Clear;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DEnable(uint cap);
        public static DEnable Enable;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDisable(uint cap);
        public static DDisable Disable;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBlendFuncSeparate(uint a, uint b, uint c, uint d);
        public static DBlendFuncSeparate BlendFuncSeparate;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDepthMask(byte flag);
        public static DDepthMask DepthMask;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDepthFunc(uint f);
        public static DDepthFunc DepthFunc;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DCullFace(uint m);
        public static DCullFace CullFace;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DFrontFace(uint m);
        public static DFrontFace FrontFace;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DReadPixels(int x, int y, int w, int h, uint format, uint type, IntPtr data);
        public static DReadPixels ReadPixels;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DPixelStorei(uint p, int v);
        public static DPixelStorei PixelStorei;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate uint DGetError();
        public static DGetError GetError;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate IntPtr DGetString(uint name);
        public static DGetString GetString;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenTextures(int n, out uint t);
        public static DGenTextures GenTextures;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindTexture(uint target, uint t);
        public static DBindTexture BindTexture;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DTexImage2D(uint target, int level, int internalFormat, int w, int h, int border, uint format, uint type, IntPtr data);
        public static DTexImage2D TexImage2D;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DTexParameteri(uint target, uint p, int v);
        public static DTexParameteri TexParameteri;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenerateMipmap(uint target);
        public static DGenerateMipmap GenerateMipmap;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DActiveTexture(uint unit);
        public static DActiveTexture ActiveTexture;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenBuffers(int n, out uint b);
        public static DGenBuffers GenBuffers;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindBuffer(uint target, uint b);
        public static DBindBuffer BindBuffer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBufferData(uint target, IntPtr size, IntPtr data, uint usage);
        public static DBufferData BufferData;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenVertexArrays(int n, out uint a);
        public static DGenVertexArrays GenVertexArrays;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindVertexArray(uint a);
        public static DBindVertexArray BindVertexArray;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DEnableVertexAttribArray(uint i);
        public static DEnableVertexAttribArray EnableVertexAttribArray;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DVertexAttribPointer(uint i, int size, uint type, byte norm, int stride, IntPtr off);
        public static DVertexAttribPointer VertexAttribPointer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDrawElements(uint mode, int count, uint type, IntPtr off);
        public static DDrawElements DrawElements;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate uint DCreateShader(uint type);
        public static DCreateShader CreateShader;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DShaderSource(uint s, int count, [MarshalAs(UnmanagedType.LPArray, ArraySubType = UnmanagedType.LPStr)] string[] src, IntPtr lengths);
        public static DShaderSource ShaderSource;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DCompileShader(uint s);
        public static DCompileShader CompileShader;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGetShaderiv(uint s, uint p, out int v);
        public static DGetShaderiv GetShaderiv;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGetShaderInfoLog(uint s, int max, out int len, [Out] byte[] log);
        public static DGetShaderInfoLog GetShaderInfoLog;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate uint DCreateProgram();
        public static DCreateProgram CreateProgram;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DAttachShader(uint p, uint s);
        public static DAttachShader AttachShader;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindAttribLocation(uint p, uint i, string name);
        public static DBindAttribLocation BindAttribLocation;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DLinkProgram(uint p);
        public static DLinkProgram LinkProgram;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGetProgramiv(uint p, uint n, out int v);
        public static DGetProgramiv GetProgramiv;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGetProgramInfoLog(uint p, int max, out int len, [Out] byte[] log);
        public static DGetProgramInfoLog GetProgramInfoLog;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUseProgram(uint p);
        public static DUseProgram UseProgram;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate int DGetUniformLocation(uint p, string name);
        public static DGetUniformLocation GetUniformLocation;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform1i(int l, int v);
        public static DUniform1i Uniform1i;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform1f(int l, float v);
        public static DUniform1f Uniform1f;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform2f(int l, float a, float b);
        public static DUniform2f Uniform2f;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform3f(int l, float a, float b, float c);
        public static DUniform3f Uniform3f;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform4f(int l, float a, float b, float c, float d);
        public static DUniform4f Uniform4f;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniform3fv(int l, int count, float[] v);
        public static DUniform3fv Uniform3fv;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniformMatrix4fv(int l, int count, byte transpose, float[] v);
        public static DUniformMatrix4fv UniformMatrix4fv;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DUniformMatrix3fv(int l, int count, byte transpose, float[] v);
        public static DUniformMatrix3fv UniformMatrix3fv;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenFramebuffers(int n, out uint f);
        public static DGenFramebuffers GenFramebuffers;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindFramebuffer(uint target, uint f);
        public static DBindFramebuffer BindFramebuffer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DFramebufferRenderbuffer(uint target, uint att, uint rbTarget, uint rb);
        public static DFramebufferRenderbuffer FramebufferRenderbuffer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DGenRenderbuffers(int n, out uint r);
        public static DGenRenderbuffers GenRenderbuffers;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBindRenderbuffer(uint target, uint r);
        public static DBindRenderbuffer BindRenderbuffer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DRenderbufferStorageMultisample(uint target, int samples, uint fmt, int w, int h);
        public static DRenderbufferStorageMultisample RenderbufferStorageMultisample;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DRenderbufferStorage(uint target, uint fmt, int w, int h);
        public static DRenderbufferStorage RenderbufferStorage;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate uint DCheckFramebufferStatus(uint target);
        public static DCheckFramebufferStatus CheckFramebufferStatus;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DBlitFramebuffer(int sx0, int sy0, int sx1, int sy1, int dx0, int dy0, int dx1, int dy1, uint mask, uint filter);
        public static DBlitFramebuffer BlitFramebuffer;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDeleteFramebuffers(int n, ref uint f);
        public static DDeleteFramebuffers DeleteFramebuffers;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DDeleteRenderbuffers(int n, ref uint r);
        public static DDeleteRenderbuffers DeleteRenderbuffers;
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] public delegate void DFinish();
        public static DFinish Finish;

        /// 载入全部函数；缺了哪个就返回它的名字（null = 全齐）
        public static string Load(Func<string, IntPtr> getProc)
        {
            string missing = null;
            T L<T>(string n) where T : class
            {
                var p = getProc("gl" + n);
                if (p == IntPtr.Zero) { missing = missing ?? ("gl" + n); return null; }
                return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
            }
            Viewport = L<DViewport>("Viewport");
            ClearColor = L<DClearColor>("ClearColor");
            Clear = L<DClear>("Clear");
            Enable = L<DEnable>("Enable");
            Disable = L<DDisable>("Disable");
            BlendFuncSeparate = L<DBlendFuncSeparate>("BlendFuncSeparate");
            DepthMask = L<DDepthMask>("DepthMask");
            DepthFunc = L<DDepthFunc>("DepthFunc");
            CullFace = L<DCullFace>("CullFace");
            FrontFace = L<DFrontFace>("FrontFace");
            ReadPixels = L<DReadPixels>("ReadPixels");
            PixelStorei = L<DPixelStorei>("PixelStorei");
            GetError = L<DGetError>("GetError");
            GetString = L<DGetString>("GetString");
            GenTextures = L<DGenTextures>("GenTextures");
            BindTexture = L<DBindTexture>("BindTexture");
            TexImage2D = L<DTexImage2D>("TexImage2D");
            TexParameteri = L<DTexParameteri>("TexParameteri");
            GenerateMipmap = L<DGenerateMipmap>("GenerateMipmap");
            ActiveTexture = L<DActiveTexture>("ActiveTexture");
            GenBuffers = L<DGenBuffers>("GenBuffers");
            BindBuffer = L<DBindBuffer>("BindBuffer");
            BufferData = L<DBufferData>("BufferData");
            GenVertexArrays = L<DGenVertexArrays>("GenVertexArrays");
            BindVertexArray = L<DBindVertexArray>("BindVertexArray");
            EnableVertexAttribArray = L<DEnableVertexAttribArray>("EnableVertexAttribArray");
            VertexAttribPointer = L<DVertexAttribPointer>("VertexAttribPointer");
            DrawElements = L<DDrawElements>("DrawElements");
            CreateShader = L<DCreateShader>("CreateShader");
            ShaderSource = L<DShaderSource>("ShaderSource");
            CompileShader = L<DCompileShader>("CompileShader");
            GetShaderiv = L<DGetShaderiv>("GetShaderiv");
            GetShaderInfoLog = L<DGetShaderInfoLog>("GetShaderInfoLog");
            CreateProgram = L<DCreateProgram>("CreateProgram");
            AttachShader = L<DAttachShader>("AttachShader");
            BindAttribLocation = L<DBindAttribLocation>("BindAttribLocation");
            LinkProgram = L<DLinkProgram>("LinkProgram");
            GetProgramiv = L<DGetProgramiv>("GetProgramiv");
            GetProgramInfoLog = L<DGetProgramInfoLog>("GetProgramInfoLog");
            UseProgram = L<DUseProgram>("UseProgram");
            GetUniformLocation = L<DGetUniformLocation>("GetUniformLocation");
            Uniform1i = L<DUniform1i>("Uniform1i");
            Uniform1f = L<DUniform1f>("Uniform1f");
            Uniform2f = L<DUniform2f>("Uniform2f");
            Uniform3f = L<DUniform3f>("Uniform3f");
            Uniform4f = L<DUniform4f>("Uniform4f");
            Uniform3fv = L<DUniform3fv>("Uniform3fv");
            UniformMatrix4fv = L<DUniformMatrix4fv>("UniformMatrix4fv");
            UniformMatrix3fv = L<DUniformMatrix3fv>("UniformMatrix3fv");
            GenFramebuffers = L<DGenFramebuffers>("GenFramebuffers");
            BindFramebuffer = L<DBindFramebuffer>("BindFramebuffer");
            FramebufferRenderbuffer = L<DFramebufferRenderbuffer>("FramebufferRenderbuffer");
            GenRenderbuffers = L<DGenRenderbuffers>("GenRenderbuffers");
            BindRenderbuffer = L<DBindRenderbuffer>("BindRenderbuffer");
            RenderbufferStorageMultisample = L<DRenderbufferStorageMultisample>("RenderbufferStorageMultisample");
            RenderbufferStorage = L<DRenderbufferStorage>("RenderbufferStorage");
            CheckFramebufferStatus = L<DCheckFramebufferStatus>("CheckFramebufferStatus");
            BlitFramebuffer = L<DBlitFramebuffer>("BlitFramebuffer");
            DeleteFramebuffers = L<DDeleteFramebuffers>("DeleteFramebuffers");
            DeleteRenderbuffers = L<DDeleteRenderbuffers>("DeleteRenderbuffers");
            Finish = L<DFinish>("Finish");
            return missing;
        }

        public static string Str(uint name) { var p = GetString(name); return p == IntPtr.Zero ? "?" : Marshal.PtrToStringAnsi(p); }
    }
}
