import AppIntents
import Foundation

// MARK: - StreamingBridge
// AppIntent의 perform()은 앱 프로세스 안에서 실행되므로 싱글톤으로 ViewModel에 접근

class StreamingBridge {
    static let shared = StreamingBridge()
    private init() {}
    weak var viewModel: TViewModel?
}

// MARK: - 캐스팅 시작 Intent

struct StartStreamingIntent: AppIntent {
    static var title: LocalizedStringResource = "TView 캐스팅 시작"
    static var description = IntentDescription(
        "TView 화면 미러링을 시작합니다. Tesla 브라우저에서 접속 URL로 이동하세요.",
        categoryName: "TView"
    )

    // Shortcuts 앱에서 검색 가능하도록 설정
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let vm = StreamingBridge.shared.viewModel else {
            return .result(dialog: "TView를 먼저 실행해 주세요.")
        }
        guard !vm.isStreaming else {
            return .result(dialog: "이미 캐스팅 중입니다. (\(vm.serverURL))")
        }
        vm.toggleStreaming()
        let url = NetworkHelper.streamingURL()
        return .result(dialog: "TView 캐스팅을 시작했습니다. Tesla 브라우저에서 \(url) 로 접속하세요.")
    }
}

// MARK: - 캐스팅 중지 Intent

struct StopStreamingIntent: AppIntent {
    static var title: LocalizedStringResource = "TView 캐스팅 중지"
    static var description = IntentDescription(
        "TView 화면 미러링을 중지합니다.",
        categoryName: "TView"
    )

    @MainActor
    func perform() async throws -> some ProvidesDialog {
        guard let vm = StreamingBridge.shared.viewModel else {
            return .result(dialog: "TView를 먼저 실행해 주세요.")
        }
        guard vm.isStreaming else {
            return .result(dialog: "현재 캐스팅 중이 아닙니다.")
        }
        vm.toggleStreaming()
        return .result(dialog: "TView 캐스팅을 중지했습니다.")
    }
}

// MARK: - Shortcuts 앱에 표시할 Intent 목록

struct TViewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartStreamingIntent(),
            phrases: [
                "\(.applicationName) 시작",
                "\(.applicationName) 캐스팅 시작"
            ],
            shortTitle: "캐스팅 시작",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopStreamingIntent(),
            phrases: [
                "\(.applicationName) 중지",
                "\(.applicationName) 캐스팅 중지"
            ],
            shortTitle: "캐스팅 중지",
            systemImageName: "stop.fill"
        )
    }
}
