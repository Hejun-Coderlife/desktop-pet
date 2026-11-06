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
        for cue in Cue.allCases { buffers[cue] = Self.load(cue, format: format) }
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

    // MARK: - 声音文件

    /// Resources/sounds/*.wav（tools/make_voice.py 生成的嗓音合成，不是哔哔的正弦波）。
    /// 打包后在 Pip.app/Contents/Resources/sounds；开发时直接用仓库里的
    private static func load(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let name = "\(cue)"
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r.appendingPathComponent("sounds/\(name).wav")) }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(repo.appendingPathComponent("Resources/sounds/\(name).wav"))
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil else { continue }
            return buf
        }
        return nil
    }
}
