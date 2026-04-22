import AVFoundation

/// 앱이 백그라운드에서도 HTTP 서버를 유지시키기 위한 무음 오디오 매니저
///
/// iOS는 백그라운드 실행을 엄격히 제한하지만, `audio` 백그라운드 모드를
/// 활성화하면 AVAudioSession이 활성 상태인 동안 앱이 계속 실행됩니다.
/// 무음(volume: 0) 오디오를 재생하여 스트리밍 서버를 백그라운드에서 유지합니다.
class BackgroundAudioManager {

    static let shared = BackgroundAudioManager()

    private let engine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var isActive = false

    private init() {}

    // MARK: - 백그라운드 오디오 시작

    func start() {
        guard !isActive else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers: 다른 앱 오디오와 공존 (음악 재생 방해 없음)
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            engine.attach(playerNode)

            // 무음 포맷으로 엔진 구성
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                print("TView: 오디오 포맷 초기화 실패")
                return
            }
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)
            engine.mainMixerNode.outputVolume = 0.0 // 완전 무음

            try engine.start()

            // 10초 무음 버퍼를 무한 반복
            let frameCount = AVAudioFrameCount(44100 * 10)
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) {
                buffer.frameLength = frameCount
                // 버퍼는 기본적으로 0(무음)으로 초기화됨
                playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
                playerNode.play()
            }

            isActive = true
        } catch {
            print("TView: 백그라운드 오디오 시작 오류 - \(error.localizedDescription)")
        }
    }

    // MARK: - 백그라운드 오디오 중지

    func stop() {
        guard isActive else { return }
        playerNode.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isActive = false
    }
}
