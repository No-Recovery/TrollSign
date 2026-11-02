import UIKit
import AVFoundation

/// Пока система скачивает IPA с нашего сервера, приложение уходит в фон.
/// Тишина в аудио-сессии + background task не дают процессу заморозиться (как у ESign).
final class KeepAlive {
    static let shared = KeepAlive()
    private var player: AVAudioPlayer?
    private var task = UIBackgroundTaskIdentifier.invalid
    private var stopWork: DispatchWorkItem?

    func start(for seconds: TimeInterval = 600) {
        if player == nil {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(data: Self.silentWAV())
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.play()
        }
        if task == .invalid {
            task = UIApplication.shared.beginBackgroundTask { [weak self] in self?.endTask() }
        }
        stopWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stop() }
        stopWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    func stop() {
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        endTask()
    }

    private func endTask() {
        if task != .invalid { UIApplication.shared.endBackgroundTask(task); task = .invalid }
    }

    private static func silentWAV() -> Data {
        let sr: UInt32 = 8000, samples = Int(sr)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(Data("RIFF".utf8)); u32(UInt32(36 + samples * 2)); d.append(Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(sr); u32(sr * 2); u16(2); u16(16)
        d.append(Data("data".utf8)); u32(UInt32(samples * 2)); d.append(Data(count: samples * 2))
        return d
    }
}
