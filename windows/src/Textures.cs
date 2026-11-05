// 程序生成的贴图，算法和 Mac 版 PipRig.faceImage / blushImage / SceneFactory.shadowImage / Fur.strandImage 逐行对应
using System;

namespace Pip
{
    /// 文字贴图由平台实现（Windows 用 GDI+；Mac 上的渲染测试没有文字）
    interface ITextRasterizer
    {
        /// 透明底文字；background 不为空时画一块带描边的圆角牌子（举牌用）
        Texture Text(string text, float fontSize, uint color, int w, int h, uint? background = null);
    }

    static class Tex
    {
        public static ITextRasterizer TextRasterizer;

        public static V3 Hex(uint v) => new V3(((v >> 16) & 0xFF) / 255f, ((v >> 8) & 0xFF) / 255f, (v & 0xFF) / 255f);

        static byte B(double v) => (byte)Math.Max(0, Math.Min(255, v));

        /// 脸：512×512 超椭圆，奶油色竖渐变 + 边缘一圈参差的暖色毛影和浅色毛尖（预乘 alpha）
        public static Texture Face()
        {
            int size = 512;
            var px = new byte[size * size * 4];
            var top = (r: 0.965, g: 0.945, b: 0.930);
            var bottom = (r: 0.950, g: 0.915, b: 0.900);
            var strands = new double[720];
            ulong seed = 0x2545F4914F6CDD1D;
            for (int i = 0; i < strands.Length; i++)
            {
                unchecked { seed = seed * 6364136223846793005UL + 1442695040888963407UL; }
                strands[i] = (double)((seed >> 33) & 0xFFFF) / 0xFFFF;
            }
            for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    double nx = (x + 0.5) / size * 2 - 1, ny = (y + 0.5) / size * 2 - 1;
                    double pw = 2.35;
                    double rho = Math.Pow(Math.Pow(Math.Abs(nx), pw) + Math.Pow(Math.Abs(ny), pw), 1 / pw);
                    double alpha = 1;
                    if (rho > 0.985) alpha = Math.Max(0, 1 - (rho - 0.985) / 0.015);
                    double t = (ny + 1) / 2;
                    double r = top.r + (bottom.r - top.r) * t, g = top.g + (bottom.g - top.g) * t, b = top.b + (bottom.b - top.b) * t;
                    double angle = Math.Atan2(ny, nx) + Math.PI;
                    int k = (int)(angle / (2 * Math.PI) * strands.Length) % strands.Length;
                    int k2 = (k + 1) % strands.Length;
                    double hair = strands[k] * 0.6 + strands[k2] * 0.4;
                    double topness = Math.Max(0, -ny);
                    double shadowWidth = (0.035 + 0.03 * topness) * (0.6 + 0.8 * hair);
                    double inside = 1 - rho;
                    if (inside < shadowWidth)
                    {
                        double u = 1 - inside / shadowWidth, shade = u * u * 0.22;
                        r += (0.80 - r) * shade; g += (0.70 - g) * shade; b += (0.64 - b) * shade;
                    }
                    double fringe = 0.012 + 0.02 * hair * (0.4 + 0.6 * topness);
                    if (inside < fringe)
                    {
                        double f = 1 - inside / fringe;
                        r += (0.965 - r) * f; g += (0.935 - g) * f; b += (0.915 - b) * f;
                    }
                    int idx = (y * size + x) * 4;
                    px[idx] = B(r * alpha * 255); px[idx + 1] = B(g * alpha * 255); px[idx + 2] = B(b * alpha * 255); px[idx + 3] = B(alpha * 255);
                }
            return new Texture { W = size, H = size, Rgba = px };
        }

        /// 径向渐变（预乘 alpha）：stops = (位置, alpha)，半径 radius 以外按 extend 决定是否保持最后一档
        static Texture Radial(int w, int h, V3 color, (double pos, double a)[] stops, double radius, bool extend)
        {
            var px = new byte[w * h * 4];
            double cx = w / 2.0, cy = h / 2.0;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double d = Math.Sqrt((x + 0.5 - cx) * (x + 0.5 - cx) + (y + 0.5 - cy) * (y + 0.5 - cy)) / radius;
                    double a;
                    if (d >= 1 && !extend) a = 0;
                    else
                    {
                        d = Math.Min(d, 1);
                        a = stops[stops.Length - 1].a;
                        for (int i = 1; i < stops.Length; i++)
                            if (d <= stops[i].pos)
                            {
                                double u = (d - stops[i - 1].pos) / (stops[i].pos - stops[i - 1].pos);
                                a = stops[i - 1].a + (stops[i].a - stops[i - 1].a) * u; break;
                            }
                    }
                    int k = (y * w + x) * 4;
                    px[k] = B(color.X * a * 255); px[k + 1] = B(color.Y * a * 255); px[k + 2] = B(color.Z * a * 255); px[k + 3] = B(a * 255);
                }
            return new Texture { W = w, H = h, Rgba = px };
        }

        /// 腮红：粉色径向渐变 0.85 → 0.32 → 0
        public static Texture Blush() => Radial(128, 128, Hex(0xF2A7A7), new[] { (0.0, 0.85), (0.5, 0.32), (1.0, 0.0) }, 64, false);

        /// 脚底阴影：128×48 画布里半径 24 的黑色径向渐变（面片 60×20 → 被横向压成小椭圆，和 Mac 版一样）
        public static Texture Shadow() => Radial(128, 48, new V3(0, 0, 0), new[] { (0.0, 0.55), (0.55, 0.28), (1.0, 0.0) }, 24, true);

        /// 毛高贴图：128×128 每像素一根毛（值 = 长度），可平铺；开 mipmap
        public static Texture Strands()
        {
            int size = 128;
            var px = new byte[size * size * 4];
            ulong seed = 0x9E3779B97F4A7C15;
            for (int i = 0; i < size * size; i++)
            {
                unchecked { seed = seed * 6364136223846793005UL + 1442695040888963407UL; }
                double r = (double)((seed >> 33) & 0xFFFFFF) / 0xFFFFFF;
                byte v = (byte)Math.Min(255, Math.Pow(r, 0.5) * 255);
                px[i * 4] = px[i * 4 + 1] = px[i * 4 + 2] = v; px[i * 4 + 3] = 255;
            }
            return new Texture { W = size, H = size, Rgba = px, Mipmap = true, Repeat = true, Gray = true };
        }

        public static Texture Text(string s, float fontSize, uint color, int w, int h, uint? bg = null)
            => TextRasterizer?.Text(s, fontSize, color, w, h, bg) ?? new Texture { W = 1, H = 1, Rgba = new byte[4] };
    }
}
