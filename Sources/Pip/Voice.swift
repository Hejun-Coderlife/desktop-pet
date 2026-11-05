import AVFoundation

/// Pip 的小声音：全部现场合成（没有音频文件），音量独立于系统音量单独调。
/// 只在有声音要放时才开音频引擎，放完 2 秒就关，平时不占音频设备。
final class Voice {
    enum Cue: CaseIterable { case grab, thrown, hop, land, petted, sign, wake }

    static let shared = Voice()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [Cue: CFTimeInterval] = [:]
    private var stopWork: DispatchWorkItem?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for cue in Cue.allCases { buffers[cue] = Self.render(cue, format: format) }
    }

    /// 状态切换时调用：挑对应的声音
    func react(from old: PetState, to new: PetState) {
        switch (old, new) {
        case (_, .grabbed): play(.grab)
        case (.grabbed, .falling): play(.thrown)
        case (_, .falling): play(.hop)
        case (.falling, .landing): play(.land)
        case (_, .petted): play(.petted)
        case (_, .sign): play(.sign)
        case (.sleep, .wake): play(.wake)
        default: break
        }
    }

    func play(_ cue: Cue) {
        let volume = Settings.volume
        guard volume > 0.001, let buffer = buffers[cue] else { return }
        let now = CACurrentMediaTime()
        if let t = lastPlayed[cue], now - t < 0.35 { return }   // 连着拎起放下时别叽叽喳喳
        lastPlayed[cue] = now

        stopWork?.cancel()
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        engine.mainMixerNode.outputVolume = Float(volume)
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.player.stop()
            self.engine.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(buffer.frameLength) / format.sampleRate + 2, execute: work)
    }

    func selfTest() {
        print("Pip 声音自检，音量 \(Int(Settings.volume * 100))%")
        for cue in Cue.allCases {
            guard let b = buffers[cue] else { continue }
            let p = b.floatChannelData![0]
            var peak: Float = 0
            for i in 0..<Int(b.frameLength) { peak = max(peak, abs(p[i])) }
            play(cue)
            let busy = SoundOutput.isPlaying()
            print("  \(cue)：\(String(format: "%.2f", Double(b.frameLength) / format.sampleRate)) 秒，峰值 \(String(format: "%.2f", peak))\(peak > 0.99 ? "（削波！）" : "")，引擎在跑=\(engine.isRunning)，被当成外部声音=\(busy)")
            RunLoop.main.run(until: Date().addingTimeInterval(Double(b.frameLength) / format.sampleRate + 0.35))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        print("  放完 2 秒后引擎已关=\(!engine.isRunning)")
    }

    // MARK: - 合成

    /// 软软的"嗓音"：基频 + 少量 2/3 次谐波 + 轻微颤音
    private static func render(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let spec = Self.spec(cue)
        let n = Int(spec.duration * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        let out = buffer.floatChannelData![0]
        var phase = 0.0, phase2 = 0.0
        var rng = SeededRNG(seed: 7)
        var noiseLP = 0.0
        for i in 0..<n {
            let t = Double(i) / sr, u = t / spec.duration
            let env = spec.envelope(u, t)
            var s = 0.0
            if let f = spec.pitch(u) {
                let vib = 1 + spec.vibrato * sin(2 * .pi * 6 * t)
                phase += 2 * .pi * f * vib / sr
                s += sin(phase) + 0.28 * sin(2 * phase) + 0.08 * sin(3 * phase)
            }
            if let f2 = spec.bell(u) {   // 铃：两组不和谐泛音
                phase2 += 2 * .pi * f2 / sr
                s += sin(phase2) + 0.35 * sin(2.76 * phase2)
            }
            if spec.noise > 0 {
                let white = Double(rng.next() % 2001) / 1000 - 1
                noiseLP += (white - noiseLP) * 0.08
                s += spec.noise * noiseLP * 3
            }
            out[i] = Float(s * env * spec.gain)
        }
        return buffer
    }

    private struct Spec {
        var duration: Double
        var gain: Double
        var vibrato = 0.0
        var noise = 0.0
        var pitch: (Double) -> Double? = { _ in nil }
        var bell: (Double) -> Double? = { _ in nil }
        var envelope: (Double, Double) -> Double
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * min(max(t, 0), 1) }
    /// 起音 a 秒、尾巴从 u=r 开始收
    private static func adsr(_ u: Double, _ t: Double, attack: Double, release: Double) -> Double {
        min(1, t / attack) * (u < release ? 1 : max(0, 1 - (u - release) / (1 - release)))
    }

    private static func spec(_ cue: Cue) -> Spec {
        switch cue {
        case .grab:     // "哇!" 往上挑
            return Spec(duration: 0.24, gain: 0.30, vibrato: 0.01,
                        pitch: { u in lerp(560, 1020, u / 0.55) },
                        envelope: { u, t in adsr(u, t, attack: 0.012, release: 0.55) })
        case .thrown:   // "咿——" 往下滑
            return Spec(duration: 0.30, gain: 0.24, vibrato: 0.02,
                        pitch: { u in lerp(980, 620, u) },
                        envelope: { u, t in adsr(u, t, attack: 0.015, release: 0.5) })
        case .hop:      // 被点了一下 "咦!"
            return Spec(duration: 0.11, gain: 0.26,
                        pitch: { u in lerp(880, 1300, u) },
                        envelope: { u, t in adsr(u, t, attack: 0.006, release: 0.45) })
        case .land:     // "噗" 软软落地
            return Spec(duration: 0.13, gain: 0.42, noise: 0.35,
                        pitch: { u in lerp(170, 70, u) },
                        envelope: { u, t in min(1, t / 0.004) * exp(-u * 5) })
        case .petted:   // "嗯~" 舒服地哼，带点呼噜的抖动
            return Spec(duration: 0.50, gain: 0.22, vibrato: 0.015,
                        pitch: { u in u < 0.4 ? lerp(600, 760, u / 0.4) : lerp(760, 680, (u - 0.4) / 0.6) },
                        envelope: { u, t in adsr(u, t, attack: 0.04, release: 0.6) * (0.75 + 0.25 * sin(2 * .pi * 11 * t)) })
        case .sign:     // "叮咚"
            return Spec(duration: 0.80, gain: 0.20,
                        bell: { u in u < 0.32 ? 1568 : 1175 },
                        envelope: { u, t in
                            let local = u < 0.32 ? t : t - 0.32 * 0.80
                            return min(1, local / 0.003) * exp(-local * 6)
                        })
        case .wake:     // "哈~欠" 起来伸懒腰
            return Spec(duration: 0.75, gain: 0.20, vibrato: 0.01, noise: 0.12,
                        pitch: { u in u < 0.35 ? lerp(380, 640, u / 0.35) : lerp(640, 320, (u - 0.35) / 0.65) },
                        envelope: { u, t in adsr(u, t, attack: 0.08, release: 0.55) })
        }
    }
}
