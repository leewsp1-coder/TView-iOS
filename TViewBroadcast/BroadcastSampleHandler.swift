import ReplayKit
import UIKit
import CoreImage

/// Broadcast Upload Extension: 전체 기기 화면을 캡처해 App Group 공유 파일로 전달
class BroadcastSampleHandler: RPBroadcastSampleHandler {

    // MARK: - 상수

    private static let appGroupID       = "group.com.tview.app"
    private static let frameFileName    = "currentFrame.jpg"
    private static let notificationName = "com.tview.newFrame" as CFString

    // MARK: - 속성

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var frameURL: URL?

    /// 프레임 레이트 / 화질 제어
    private var lastFrameTime: CFTimeInterval = 0
    private var targetInterval: TimeInterval = 1.0 / 24.0
    private var jpegQuality:    CGFloat       = 0.65
    /// GPU 스케일링 목표 너비 (0 = 원본 유지)
    private var targetWidth:    CGFloat       = 1280
    /// 품질 재확인 주기 카운터 (매 60프레임마다 UserDefaults 재읽기)
    private var frameCount:     Int           = 0

    // MARK: - 생명주기

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) else {
            finishBroadcastWithError(makeError("App Group 컨테이너를 찾을 수 없습니다."))
            return
        }
        frameURL = containerURL.appendingPathComponent(Self.frameFileName)
        readQualitySettings()
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}
    override func broadcastFinished() {}

    // MARK: - 프레임 처리

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        // 매 60프레임(약 2~4초)마다 품질 설정 재확인 → 브로드캐스트 중 품질 변경 즉시 반영
        frameCount += 1
        if frameCount % 60 == 0 {
            readQualitySettings()
        }

        // 목표 FPS로 제한
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= targetInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frameURL else { return }

        // GPU 스케일링 (Metal 가속): 목표 너비보다 클 때만 축소
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let srcW = ciImage.extent.width
        if targetWidth > 0, srcW > targetWidth {
            let s = targetWidth / srcW
            ciImage = ciImage.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }

        // JPEG 인코딩 (소프트웨어 → GPU 변환 후 CPU 압축)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality) else { return }

        // 공유 컨테이너에 원자적으로 쓰기 (부분 읽기 방지)
        try? jpegData.write(to: frameURL, options: .atomic)

        // 메인 앱에 새 프레임 도착 알림 (Darwin cross-process notification)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Self.notificationName),
            nil, nil, true
        )
    }

    // MARK: - 품질 설정 읽기 (공유 UserDefaults)

    private func readQualitySettings() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        // StreamingQuality 열거형의 수치를 미러링 (공유 프레임워크 없이 직접 매핑)
        switch defaults.string(forKey: "tv.streamingQuality") {
        case "고화질":   // StreamingQuality.high  — 1920px · 30fps
            targetInterval = 1.0 / 30.0
            jpegQuality    = 0.80
            targetWidth    = 1920
        case "저화질":   // StreamingQuality.low   — 854px · 15fps
            targetInterval = 1.0 / 15.0
            jpegQuality    = 0.45
            targetWidth    = 854
        default:         // .auto / .medium         — 1280px · 24fps
            targetInterval = 1.0 / 24.0
            jpegQuality    = 0.65
            targetWidth    = 1280
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "com.tview.broadcast", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
