// 极简 PNG 编码（自检截图、图标用）。.NET Framework 没有 ZLibStream，手写 zlib 头 + Adler32
using System;
using System.IO;
using System.IO.Compression;

namespace Pip
{
    static class Png
    {
        static uint[] crcTable;
        static uint Crc(byte[] b)
        {
            if (crcTable == null)
            {
                crcTable = new uint[256];
                for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; crcTable[n] = c; }
            }
            uint crc = 0xFFFFFFFF; foreach (var x in b) crc = crcTable[(crc ^ x) & 0xFF] ^ (crc >> 8); return crc ^ 0xFFFFFFFF;
        }
        static void BE(Stream s, uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
        static void Chunk(Stream s, string type, byte[] data)
        {
            BE(s, (uint)data.Length);
            var buf = new byte[4 + data.Length];
            System.Text.Encoding.ASCII.GetBytes(type).CopyTo(buf, 0); data.CopyTo(buf, 4);
            s.Write(buf, 0, buf.Length); BE(s, Crc(buf));
        }

        /// rgba：自上而下、非预乘
        public static byte[] Encode(byte[] rgba, int w, int h)
        {
            var raw = new byte[(w * 4 + 1) * h];
            for (int y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.BlockCopy(rgba, y * w * 4, raw, y * (w * 4 + 1) + 1, w * 4); }
            var z = new MemoryStream();
            z.WriteByte(0x78); z.WriteByte(0x9C);
            using (var ds = new DeflateStream(z, CompressionLevel.Optimal, true)) ds.Write(raw, 0, raw.Length);
            uint a = 1, b = 0; foreach (var x in raw) { a = (a + x) % 65521; b = (b + a) % 65521; }
            BE(z, (b << 16) | a);
            var f = new MemoryStream();
            f.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
            var ihdr = new MemoryStream(); BE(ihdr, (uint)w); BE(ihdr, (uint)h); ihdr.Write(new byte[] { 8, 6, 0, 0, 0 }, 0, 5);
            Chunk(f, "IHDR", ihdr.ToArray()); Chunk(f, "IDAT", z.ToArray()); Chunk(f, "IEND", new byte[0]);
            return f.ToArray();
        }

        /// 渲染器读回的像素（BGRA、自下而上、预乘）→ RGBA 自上而下非预乘
        public static byte[] FromRender(byte[] bgra, int w, int h)
        {
            var o = new byte[w * h * 4];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int i = ((h - 1 - y) * w + x) * 4, j = (y * w + x) * 4; byte al = bgra[i + 3];
                    byte un(byte c) => al == 0 ? (byte)0 : (byte)Math.Min(255, c * 255 / al);
                    o[j] = un(bgra[i + 2]); o[j + 1] = un(bgra[i + 1]); o[j + 2] = un(bgra[i]); o[j + 3] = al;
                }
            return o;
        }

        public static void SaveRender(string path, byte[] bgra, int w, int h) => File.WriteAllBytes(path, Encode(FromRender(bgra, w, h), w, h));
    }
}
