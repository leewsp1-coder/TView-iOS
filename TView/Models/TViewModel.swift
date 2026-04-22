import SwiftUI

enum StreamingQuality: String, CaseIterable {
    case auto   = "자동"
    case high   = "고화질"
    case medium = "중화질"
    case low    = "저화질"

    /// GPU 스케일링 목표 너비 (픽셀)
    var targetWidth: CGFloat {
        switch self {
        case .high:          return 1920
        case .auto, .medium: return 1280
        case .low:           return 854
        }
    }

    /// 목표 FPS
    var targetFPS: Int {
        switch self {
        case .high:          return 30
        case .auto, .medium: return 24
        case .low:           return 15
        }
    }

    /// JPEG 품질
    var jpegQuality: CGFloat {
        switch self {
        case .high:          return 0.80
        case .auto, .medium: return 0.65
        case .low:           return 0.45
        }
    }

    /// UI 표시용 상세 설명 (품질 피커 하단)
    var resolutionDetail: String {
        switch self {
        case .auto:
            return "하드웨어 자동 · 최대 1280px · 24fps"
        case .high:
            return "최대 1920px · 30fps · 고화질 (MCU3 권장)"
        case .medium:
            return "최대 1280px · 24fps · 균형 (권장)"
        case .low:
            return "최대 854px · 15fps · 절전 / 저사양"
        }
    }

    /// 피커 항목 표시 레이블
    var pickerLabel: String {
        switch self {
        case .auto:   return "자동"
        case .high:   return "고화질 1920p"
        case .medium: return "중화질 1280p"
        case .low:    return "저화질 854p"
        }
    }
}

enum TeslaHardware: String, CaseIterable {
    case auto = "자동"
    case mcu2 = "MCU2"
    case mcu3 = "MCU3"
}

enum AppTheme: String, CaseIterable {
    case system = "시스템"
    case light  = "라이트"
    case dark   = "다크"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case system  = "시스템"
    case korean  = "한국어"
    case english = "English"
}

enum StreamingState {
    case disconnected
    case connecting
    case streaming

    var text: String {
        switch self {
        case .disconnected: return "연결 안 됨"
        case .connecting:   return "연결 중..."
        case .streaming:    return "스트리밍 중"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .gray
        case .connecting:   return .yellow
        case .streaming:    return .green
        }
    }
}

// MARK: - UserDefaults 키 상수

private enum UDKey {
    static let quality      = "tv.streamingQuality"
    static let hardware     = "tv.teslaHardware"
    static let useVPN       = "tv.useVPNIP"
    static let batterySaver = "tv.batterySaverMode"
    static let thermal      = "tv.thermalManagement"
    static let varFPS       = "tv.variableFPS"
    static let safeGuard    = "tv.safeDrivingGuardEnabled"
    static let autoStart    = "tv.autoStartEnabled"
    static let theme        = "tv.theme"
    static let language     = "tv.language"
}

private let ud = UserDefaults.standard

// MARK: - ViewModel

@MainActor
class TViewModel: ObservableObject {

    // MARK: - UI 상태 (저장 불필요)

    @Published var selectedTab = 0
    @Published var isStreaming = false
    @Published var streamingState: StreamingState = .disconnected
    @Published var serverURL: String = ""
    @Published var localURL: String = ""
    @Published var errorMessage: String? = nil

    // MARK: - 설정 (UserDefaults에 자동 저장 + 실시간 반영)

    @Published var streamingQuality: StreamingQuality =
        StreamingQuality(rawValue: ud.string(forKey: UDKey.quality) ?? "") ?? .auto {
        didSet {
            ud.set(streamingQuality.rawValue, forKey: UDKey.quality)
            applyQualityChange()
        }
    }

    @Published var teslaHardware: TeslaHardware =
        TeslaHardware(rawValue: ud.string(forKey: UDKey.hardware) ?? "") ?? .auto {
        didSet {
            ud.set(teslaHardware.rawValue, forKey: UDKey.hardware)
            applyQualityChange()
        }
    }

    @Published var useVPNIP: Bool = ud.bool(forKey: UDKey.useVPN) {
        didSet {
            ud.set(useVPNIP, forKey: UDKey.useVPN)
            // 스트리밍 중이면 즉시 URL 갱신
            if isStreaming {
                serverURL = NetworkHelper.streamingURL(useVPN: useVPNIP)
            }
        }
    }

    @Published var batterySaverMode: Bool = ud.bool(forKey: UDKey.batterySaver) {
        didSet {
            ud.set(batterySaverMode, forKey: UDKey.batterySaver)
            applyQualityChange()
        }
    }

    @Published var thermalManagement: Bool =
        (ud.object(forKey: UDKey.thermal) as? Bool) ?? true {
        didSet {
            ud.set(thermalManagement, forKey: UDKey.thermal)
            // 발열 관리 비활성화 시 강제로 낮춘 품질을 원래대로 복원
            if !thermalManagement { applyQualityChange() }
        }
    }

    @Published var variableFPS: Bool =
        (ud.object(forKey: UDKey.varFPS) as? Bool) ?? true {
        didSet {
            ud.set(variableFPS, forKey: UDKey.varFPS)
            screenCapture.variableFPS = variableFPS
        }
    }

    @Published var safeDrivingGuardEnabled: Bool =
        (ud.object(forKey: UDKey.safeGuard) as? Bool) ?? true {
        didSet {
            ud.set(safeDrivingGuardEnabled, forKey: UDKey.safeGuard)
            guard isStreaming else { return }
            if !safeDrivingGuardEnabled {
                // 가드 비활성화: 잠금만 해제, 위치 모니터링은 유지 (HUD 데이터용)
                streamingServer.setDrivingLocked(false)
            }
            // 가드 활성화 시에도 startMonitoring은 이미 streaming 시작 시 호출됨
        }
    }

    @Published var autoStartEnabled: Bool = ud.bool(forKey: UDKey.autoStart) {
        didSet { ud.set(autoStartEnabled, forKey: UDKey.autoStart) }
    }

    @Published var theme: AppTheme =
        AppTheme(rawValue: ud.string(forKey: UDKey.theme) ?? "") ?? .system {
        didSet { ud.set(theme.rawValue, forKey: UDKey.theme) }
    }

    @Published var language: AppLanguage =
        AppLanguage(rawValue: ud.string(forKey: UDKey.language) ?? "") ?? .system {
        didSet { ud.set(language.rawValue, forKey: UDKey.language) }
    }

    // MARK: - 스트리밍 컴포넌트

    private let streamingServer = StreamingServer()
    private let screenCapture = ScreenCaptureManager()
    let safeDrivingGuard = SafeDrivingGuard()
    var cameraDataUpdater = CameraDataUpdater()

    // MARK: - 초기화

    init() {
        setupCapture()
        setupDrivingGuard()
        setupThermalManagement()
        StreamingBridge.shared.viewModel = self
    }

    private func setupCapture() {
        screenCapture.onFrame = { [weak self] data in
            self?.streamingServer.updateFrame(data)
        }
    }

    private func setupDrivingGuard() {
        safeDrivingGuard.onDrivingStateChanged = { [weak self] isDriving in
            guard let self else { return }
            let shouldLock = self.safeDrivingGuardEnabled && isDriving
            self.streamingServer.setDrivingLocked(shouldLock)
        }
    }

    /// 발열 상태 변화 감지 → 자동 품질 조절
    private func setupThermalManagement() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalStateChange()
            }
        }
    }

    private func handleThermalStateChange() {
        guard thermalManagement, isStreaming else { return }
        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            screenCapture.updateQuality(.medium, hardware: teslaHardware)
        case .critical:
            screenCapture.updateQuality(.low, hardware: teslaHardware)
        default:
            applyQualityChange() // 정상 복귀 시 사용자 설정으로 복원
        }
    }

    // MARK: - 스트리밍 제어

    func toggleStreaming() {
        if isStreaming { stopStreaming() } else { startStreaming() }
    }

    private func startStreaming() {
        streamingState = .connecting
        isStreaming = true
        errorMessage = nil

        do {
            try streamingServer.start()
        } catch {
            streamingState = .disconnected
            isStreaming = false
            errorMessage = "서버 시작 실패: \(error.localizedDescription)"
            return
        }

        let effectiveQuality = batterySaverMode ? StreamingQuality.low : streamingQuality
        screenCapture.variableFPS = variableFPS
        screenCapture.start(quality: effectiveQuality, hardware: teslaHardware)

        // 가드 ON/OFF 무관하게 항상 위치 모니터링 시작 → HUD 속도/방향 데이터 확보
        safeDrivingGuard.startMonitoring()

        BackgroundAudioManager.shared.start()

        serverURL = NetworkHelper.streamingURL(useVPN: useVPNIP)
        localURL  = NetworkHelper.localURL()
        streamingState = .streaming
    }

    private func stopStreaming() {
        streamingServer.stop()
        screenCapture.stop()
        safeDrivingGuard.stopMonitoring()
        BackgroundAudioManager.shared.stop()

        isStreaming = false
        streamingState = .disconnected
        serverURL = ""
        localURL = ""
    }

    // MARK: - 품질 동기화

    /// 현재 설정값을 ScreenCaptureManager에 반영
    func applyQualityChange() {
        guard isStreaming else { return }
        let effectiveQuality = batterySaverMode ? StreamingQuality.low : streamingQuality
        screenCapture.updateQuality(effectiveQuality, hardware: teslaHardware)
        screenCapture.variableFPS = variableFPS
    }

    func syncHUDToServer() {
        let cam = safeDrivingGuard.cameraManager
        streamingServer.updateHUD(
            speed: safeDrivingGuard.speed,
            heading: safeDrivingGuard.heading,
            cameraDistance: cam.distanceToNearest,
            cameraSpeedLimit: cam.nearestCamera?.limit ?? 0,
            cameraType: cam.nearestCamera?.type ?? "",
            cameraAlertLevel: cam.alertLevel.rawValue
        )
    }

    // MARK: - 설정 초기화

    func resetSettings() {
        streamingQuality       = .auto
        teslaHardware          = .auto
        useVPNIP               = false
        batterySaverMode       = false
        thermalManagement      = true
        variableFPS            = true
        safeDrivingGuardEnabled = true
        autoStartEnabled       = false
        theme                  = .system
        language               = .system
    }
}
