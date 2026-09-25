// 第二版音效合成（枪声、机械声、命中、卖东西、海鸥、水下）。
// 用法（Windows，不用装任何东西）：powershell -ExecutionPolicy Bypass -File tools/gen_sfx2.ps1
// 每个声音分层合成：爆裂声（高频噪声）+ 枪身（带通噪声）+ 低频冲击（下滑正弦）+ 机械声（金属共振）+ 回声尾巴（混响），最后软削波加厚度。
using System;
using System.IO;
using System.Collections.Generic;

public static class GenSfx2
{
    const int SR = 44100;
    static Random rng = new Random(7);

    static double Noise() { return rng.NextDouble() * 2.0 - 1.0; }

    static double[] Buf(double seconds) { return new double[(int)(seconds * SR)]; }

    // ---------------------------------------------------------------- 滤波
    static void LowPass(double[] x, double hz)
    {
        double a = Math.Exp(-2.0 * Math.PI * hz / SR), y = 0;
        for (int i = 0; i < x.Length; i++) { y = (1 - a) * x[i] + a * y; x[i] = y; }
    }

    static void HighPass(double[] x, double hz)
    {
        double a = Math.Exp(-2.0 * Math.PI * hz / SR), y = 0, prev = 0;
        for (int i = 0; i < x.Length; i++) { y = a * (y + x[i] - prev); prev = x[i]; x[i] = y; }
    }

    static void BandPass(double[] x, double hz, double q)
    {
        double w = 2 * Math.PI * hz / SR, alpha = Math.Sin(w) / (2 * q), cw = Math.Cos(w);
        double b0 = alpha, b1 = 0, b2 = -alpha, a0 = 1 + alpha, a1 = -2 * cw, a2 = 1 - alpha;
        double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
        for (int i = 0; i < x.Length; i++)
        {
            double y = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
            x2 = x1; x1 = x[i]; y2 = y1; y1 = y; x[i] = y;
        }
    }

    // ---------------------------------------------------------------- 基本声音
    static double[] NoiseBurst(double len, double tau, double delay)
    {
        var b = Buf(len);
        for (int i = (int)(delay * SR); i < b.Length; i++)
        {
            double t = (double)i / SR - delay;
            b[i] = Noise() * Math.Exp(-t / tau) * Math.Min(t / 0.0005 + 0.02, 1.0);
        }
        return b;
    }

    static double[] Sweep(double len, double f0, double f1, double sweepT, double tau, double delay)
    {
        var b = Buf(len);
        double ph = 0;
        for (int i = (int)(delay * SR); i < b.Length; i++)
        {
            double t = (double)i / SR - delay;
            double f = f1 + (f0 - f1) * Math.Exp(-t / sweepT);
            ph += 2 * Math.PI * f / SR;
            b[i] = Math.Sin(ph) * Math.Exp(-t / tau) * Math.Min(t / 0.001, 1.0);
        }
        return b;
    }

    // 金属零件撞一下：几个不成谐波的共振 + 一点噪声
    static double[] Clack(double len, double delay, double f, double tau, double amp)
    {
        var b = Buf(len);
        double[] ratios = { 1.0, 1.47, 2.09, 2.76 };
        for (int i = (int)(delay * SR); i < b.Length; i++)
        {
            double t = (double)i / SR - delay;
            double v = 0;
            for (int k = 0; k < ratios.Length; k++)
                v += Math.Sin(2 * Math.PI * f * ratios[k] * t + k) * Math.Exp(-t / (tau / (1 + k * 0.6))) / (1 + k);
            v += Noise() * Math.Exp(-t / 0.002) * 0.8;
            b[i] = v * amp;
        }
        return b;
    }

    // 金属滑动（拉栓、滑套）
    static double[] Slide(double len, double from, double to, double hz, double amp)
    {
        var b = Buf(len);
        for (int i = (int)(from * SR); i < Math.Min(b.Length, (int)(to * SR)); i++)
        {
            double t = ((double)i / SR - from) / (to - from);
            b[i] = Noise() * Math.Sin(Math.PI * t) * amp * (0.6 + 0.4 * Math.Sin(t * 90));
        }
        BandPass(b, hz, 1.2);
        return b;
    }

    static void Mix(double[] dst, double[] src, double g)
    {
        for (int i = 0; i < Math.Min(dst.Length, src.Length); i++) dst[i] += src[i] * g;
    }

    // Schroeder 混响：4 个梳状 + 2 个全通
    static double[] Reverb(double[] x, double decay, double lp)
    {
        var y = new double[x.Length];
        int[] combs = { 1557, 1617, 1491, 1422 };
        foreach (int d in combs)
        {
            double g = Math.Pow(0.001, (double)d / SR / decay);
            var buf = new double[d];
            int p = 0; double f = 0;
            for (int i = 0; i < x.Length; i++)
            {
                double o = buf[p];
                f = o * 0.7 + f * 0.3;
                buf[p] = x[i] + f * g;
                p = (p + 1) % d;
                y[i] += o * 0.25;
            }
        }
        int[] aps = { 225, 556 };
        foreach (int d in aps)
        {
            var buf = new double[d];
            int p = 0;
            for (int i = 0; i < y.Length; i++)
            {
                double o = buf[p];
                double v = y[i] + o * 0.5;
                buf[p] = v;
                y[i] = o - v * 0.5;
                p = (p + 1) % d;
            }
        }
        LowPass(y, lp);
        return y;
    }

    static void Saturate(double[] x, double drive)
    {
        double n = Math.Tanh(drive);
        for (int i = 0; i < x.Length; i++) x[i] = Math.Tanh(x[i] * drive) / n;
    }

    static void Fade(double[] x, double outT)
    {
        int n = (int)(outT * SR);
        for (int i = 0; i < n && i < x.Length; i++) x[x.Length - 1 - i] *= (double)i / n;
    }

    static void Save(string dir, string name, double[] x, double peak)
    {
        double m = 1e-9;
        foreach (double v in x) m = Math.Max(m, Math.Abs(v));
        double g = peak / m;
        using (var fs = new FileStream(Path.Combine(dir, name + ".wav"), FileMode.Create))
        using (var w = new BinaryWriter(fs))
        {
            int bytes = x.Length * 2;
            w.Write(new char[] { 'R', 'I', 'F', 'F' }); w.Write(36 + bytes);
            w.Write(new char[] { 'W', 'A', 'V', 'E' }); w.Write(new char[] { 'f', 'm', 't', ' ' });
            w.Write(16); w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new char[] { 'd', 'a', 't', 'a' }); w.Write(bytes);
            foreach (double v in x) w.Write((short)Math.Max(-32767, Math.Min(32767, v * g * 32767)));
        }
    }

    // ---------------------------------------------------------------- 枪声
    static double[] Gunshot(double len, double crack, double bodyHz, double bodyTau, double thumpF0, double thumpF1, double thumpTau,
                            double thumpGain, double tailDecay, double tailMix, double drive, double twang)
    {
        var dry = Buf(len);
        var c = NoiseBurst(len, 0.0035, 0); HighPass(c, 2500); Mix(dry, c, crack * 1.6);
        var body = NoiseBurst(len, bodyTau, 0.0006); BandPass(body, bodyHz, 0.7); Mix(dry, body, 2.2);
        var low = NoiseBurst(len, bodyTau * 1.6, 0.0); LowPass(low, 400); Mix(dry, low, 1.3);
        Mix(dry, Sweep(len, thumpF0, thumpF1, 0.03, thumpTau, 0), thumpGain);
        Mix(dry, Clack(len, 0.0, 3100, 0.012, 0.25), 1.0);          // 击锤 / 机括
        if (twang > 0)
        {
            // 弩弦回弹：低沉的"嘣"，保留一点暗器味道
            var tw = Buf(len); double ph = 0;
            for (int i = 0; i < tw.Length; i++)
            {
                double t = (double)i / SR; double f = 150 * (1 + 0.4 * Math.Exp(-t / 0.02));
                ph += 2 * Math.PI * f / SR;
                tw[i] = (Math.Sin(ph) + 0.4 * Math.Sin(2 * ph) + 0.2 * Math.Sin(3 * ph)) * Math.Exp(-t / 0.09);
            }
            Mix(dry, tw, twang);
        }
        Saturate(dry, drive);
        var tail = Reverb(dry, tailDecay, 3200);
        var outp = Buf(len);
        Mix(outp, dry, 1.0);
        Mix(outp, tail, tailMix * 2.5);
        // 远处山谷的回声：延迟 0.18 秒的一小份
        int d = (int)(0.18 * SR);
        for (int i = outp.Length - 1; i >= d; i--) outp[i] += tail[i - d] * tailMix * 0.8;
        Fade(outp, 0.08);
        return outp;
    }

    public static void Run(string dir)
    {
        Directory.CreateDirectory(dir);
        // 暗器开火
        Save(dir, "xiujian_fire", Gunshot(0.9, 0.9, 1300, 0.035, 170, 60, 0.05, 0.9, 0.9, 0.28, 2.6, 0.25), 0.95);
        Save(dir, "zhuge_fire", Gunshot(0.55, 0.8, 1600, 0.024, 150, 70, 0.035, 0.8, 0.5, 0.18, 2.4, 0.18), 0.9);
        Save(dir, "kongque_fire", Gunshot(1.3, 1.0, 950, 0.05, 125, 45, 0.08, 1.15, 1.3, 0.34, 3.0, 0.2), 0.97);
        var sg = Gunshot(1.6, 0.8, 620, 0.09, 95, 35, 0.14, 1.5, 1.5, 0.4, 3.6, 0.1);
        for (int k = 0; k < 14; k++) { var pc = NoiseBurst(1.6, 0.002, 0.004 + rng.NextDouble() * 0.02); HighPass(pc, 3000); Mix(sg, pc, 0.25); }
        Save(dir, "baoyu_fire", sg, 0.98);
        Save(dir, "zhuihun_fire", Gunshot(2.2, 1.0, 720, 0.07, 85, 30, 0.16, 1.6, 2.2, 0.5, 4.0, 0.35), 0.98);

        // 换弹、拉栓、泵动
        var mo = Buf(0.45); Mix(mo, Clack(0.45, 0.0, 3300, 0.01, 0.7), 1); Mix(mo, Slide(0.45, 0.03, 0.14, 2200, 0.5), 1); Mix(mo, Clack(0.45, 0.2, 700, 0.03, 0.5), 1);
        Save(dir, "mag_out", mo, 0.7);
        var mi = Buf(0.45); Mix(mi, Slide(0.45, 0.0, 0.09, 1800, 0.5), 1); Mix(mi, Clack(0.45, 0.1, 1900, 0.025, 1.0), 1); Mix(mi, Clack(0.45, 0.16, 3600, 0.01, 0.6), 1);
        Save(dir, "mag_in", mi, 0.8);
        var bc = Buf(0.7); Mix(bc, Clack(0.7, 0.0, 2800, 0.012, 0.7), 1); Mix(bc, Slide(0.7, 0.06, 0.22, 2500, 0.6), 1); Mix(bc, Clack(0.7, 0.23, 1600, 0.02, 0.6), 1);
        Mix(bc, Slide(0.7, 0.32, 0.44, 2300, 0.5), 1); Mix(bc, Clack(0.7, 0.46, 2100, 0.025, 1.0), 1);
        Save(dir, "bolt_cycle", bc, 0.8);
        var pu = Buf(0.55); Mix(pu, Slide(0.55, 0.0, 0.1, 1200, 0.7), 1); Mix(pu, Clack(0.55, 0.1, 1100, 0.03, 1.0), 1);
        Mix(pu, Slide(0.55, 0.2, 0.29, 1400, 0.6), 1); Mix(pu, Clack(0.55, 0.3, 1500, 0.03, 1.0), 1);
        Save(dir, "pump", pu, 0.85);
        var sh = Buf(0.3); Mix(sh, Slide(0.3, 0.0, 0.06, 1600, 0.4), 1); Mix(sh, Clack(0.3, 0.06, 1300, 0.02, 0.9), 1);
        Save(dir, "reload_shell", sh, 0.7);
        Save(dir, "dry", Clack(0.2, 0.0, 3800, 0.008, 1.0), 0.5);
        var sw = Buf(0.4); var cloth = NoiseBurst(0.4, 0.08, 0); BandPass(cloth, 900, 0.6); Mix(sw, cloth, 0.6); Mix(sw, Clack(0.4, 0.12, 2400, 0.015, 0.8), 1);
        Save(dir, "switch", sw, 0.6);
        var ai = NoiseBurst(0.25, 0.05, 0); BandPass(ai, 1100, 0.5); Mix(ai, Clack(0.25, 0.07, 3000, 0.006, 0.25), 1);
        Save(dir, "ads_in", ai, 0.35);
        var tink = Buf(0.5); for (int k = 0; k < 3; k++) Mix(tink, Clack(0.5, 0.05 + k * 0.09 + rng.NextDouble() * 0.03, 4800 + rng.Next(1500), 0.03, 0.6 / (k + 1)), 1);
        Save(dir, "shell", tink, 0.35);
        Save(dir, "low_ammo", Clack(0.15, 0.0, 5200, 0.006, 1.0), 0.3);

        // 命中：像 CoD 的命中提示音，干脆
        var hit = Buf(0.18); Mix(hit, Clack(0.18, 0.0, 4200, 0.012, 0.9), 1); var th = NoiseBurst(0.18, 0.02, 0); LowPass(th, 900); Mix(hit, th, 0.9);
        Save(dir, "hit", hit, 0.75);
        var hh = Buf(0.5); Mix(hh, Clack(0.5, 0.0, 4200, 0.012, 0.8), 1);
        for (int i = 0; i < hh.Length; i++) { double t = (double)i / SR; hh[i] += (Math.Sin(2 * Math.PI * 2250 * t) + 0.6 * Math.Sin(2 * Math.PI * 3370 * t)) * Math.Exp(-t / 0.11) * 0.5; }
        Save(dir, "hit_head", hh, 0.8);

        // 卖东西：一串金币 + 收银
        var sell = Buf(1.0);
        for (int k = 0; k < 9; k++) Mix(sell, Clack(1.0, k * 0.045 + rng.NextDouble() * 0.02, 2600 + rng.Next(2200), 0.06, 0.5), 1);
        for (int i = 0; i < sell.Length; i++) { double t = (double)i / SR - 0.35; if (t > 0) sell[i] += (Math.Sin(2 * Math.PI * 1568 * t) + Math.Sin(2 * Math.PI * 2093 * t)) * Math.Exp(-t / 0.25) * 0.35; }
        Save(dir, "sell", Reverbed(sell, 0.6, 0.15), 0.8);
        var pk = Buf(0.25); double pp = 0;
        for (int i = 0; i < pk.Length; i++) { double t = (double)i / SR; double f = 600 + 900 * Math.Min(t / 0.06, 1); pp += 2 * Math.PI * f / SR; pk[i] = Math.Sin(pp) * Math.Exp(-t / 0.05) * 0.6; }
        Mix(pk, Clack(0.25, 0.0, 3000, 0.01, 0.3), 1);
        Save(dir, "pickup", pk, 0.6);

        // 海鸥叫
        var gull = Buf(1.1);
        for (int r = 0; r < 3; r++)
        {
            double st = r * 0.28, dur = r == 2 ? 0.42 : 0.2; double ph = 0;
            for (int i = (int)(st * SR); i < Math.Min(gull.Length, (int)((st + dur) * SR)); i++)
            {
                double t = (double)i / SR - st, k = t / dur;
                double f = 1750 - 850 * k + 60 * Math.Sin(t * 2 * Math.PI * 38);
                ph += 2 * Math.PI * f / SR;
                double env = Math.Sin(Math.PI * Math.Min(k * 1.2, 1.0));
                gull[i] += (Math.Sin(ph) + 0.5 * Math.Sin(2 * ph) + 0.3 * Math.Sin(3 * ph) + Noise() * 0.25) * env * 0.5;
            }
        }
        BandPass(gull, 1500, 0.5);
        Save(dir, "gull_cry", Reverbed(gull, 0.8, 0.2), 0.8);

        // 水：落水、水下的咕噜声、出水喘气
        var wi = NoiseBurst(1.0, 0.12, 0); LowPass(wi, 1200);
        for (int k = 0; k < 16; k++)
        {
            double st = 0.05 + rng.NextDouble() * 0.6; double f0 = 300 + rng.NextDouble() * 500; double ph = 0;
            for (int i = (int)(st * SR); i < Math.Min(wi.Length, (int)((st + 0.05) * SR)); i++)
            { double t = (double)i / SR - st; ph += 2 * Math.PI * f0 * (1 + t * 12) / SR; wi[i] += Math.Sin(ph) * Math.Exp(-t / 0.015) * 0.3; }
        }
        Save(dir, "water_in", wi, 0.7);
        var gasp = NoiseBurst(0.6, 0.2, 0);
        for (int i = 0; i < gasp.Length; i++) { double t = (double)i / SR; gasp[i] *= Math.Min(t / 0.12, 1.0); }
        BandPass(gasp, 1300, 0.8);
        Save(dir, "gasp", gasp, 0.55);
        var rev = Buf(0.9); double rp = 0;
        for (int i = 0; i < rev.Length; i++) { double t = (double)i / SR; double f = 440 * Math.Pow(2, Math.Floor(t / 0.15) * 4 / 12.0); rp += 2 * Math.PI * f / SR; rev[i] = Math.Sin(rp) * Math.Exp(-(t % 0.15) / 0.12) * 0.5; }
        Save(dir, "revive", Reverbed(rev, 0.8, 0.2), 0.6);
    }

    static double[] Reverbed(double[] x, double decay, double mix)
    {
        var r = Reverb(x, decay, 5000);
        var o = new double[x.Length];
        for (int i = 0; i < x.Length; i++) o[i] = x[i] + r[i] * mix * 2.5;
        Fade(o, 0.05);
        return o;
    }
}
