import Foundation
import UIKit

/// App Group 공유 파일 + Darwin notification으로 Broadcast Extension에서 프레임을 수신
/// Broadcast Extension(TViewBroadcast)이 기기 전체 화면을 캡처 → JPEG 저장 → 알림 전송
/// → 이 매니저가 수신 → HTTP 서버로 전달
class ScreenCaptureManager {

    // MARK: - 콜백

    var onFrame: ((Data) -> Void)?

    /// 호환성 유지용 (실제 제어는 Extension이 담당)
    var variableFPS: Bool = false

    // MARK: - 상태

    private(set) var isCapturing = false

    // MARK: - 상수

    private static let appGroupID       = "group.com.tview.app"
    private static let frameFileName    = "currentFrame.jpg"
    private static let notificationName = "com.tview.newFrame"

    // MARK: - 공유 컨테이너 경로

    private var frameURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.frameFileName)
    }

    // MARK: - 생명주기

    deinit {
        if isCapturing {
            unregisterDarwinObserver()
        }
    }

    // MARK: - 캡처 시작 / 중지

    func start(quality: StreamingQuality, hardware: TeslaHardware) {
        saveQualityToShared(quality: quality)
        isCapturing = true
        registerDarwinObserver()
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        unregisterDarwinObserver()
    }

    func updateQuality(_ quality: StreamingQuality, hardware: TeslaHardware = .auto) {
        saveQualityToShared(quality: quality)
    }

    // MARK: - Darwin Notification

    private func registerDarwinObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            ScreenCaptureManager.darwinCallback,
            Self.notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func unregisterDarwinObserver() {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(Self.notificationName as CFString),
            nil
        )
    }

    /// C 함수 포인터 형식 콜백 (static 필수)
    private static let darwinCallback: CFNotificationCallback = { _, observer, _, _, _ in
        guard let observer else { return }
        let manager = Unmanaged<ScreenCaptureManager>.fromOpaque(observer).takeUnretainedValue()
        manager.handleNewFrame()
    }

    private func handleNewFrame() {
        guard isCapturing, let url = frameURL else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        onFrame?(data)
    }

    // MARK: - 품질 설정 공유 (Extension이 브로드캐스트 시작 시 읽음)

    private func saveQualityToShared(quality: StreamingQuality) {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        defaults?.set(quality.rawValue, forKey: "tv.streamingQuality")
        defaults?.synchronize()
    }
}
