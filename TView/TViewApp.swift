import SwiftUI

@main
struct TViewApp: App {
    @StateObject private var viewModel = TViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                // 앱이 포그라운드로 돌아올 때 자동 시작 확인
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification
                    )
                ) { _ in
                    if viewModel.autoStartEnabled && !viewModel.isStreaming {
                        viewModel.toggleStreaming()
                    }
                }
                // 앱이 백그라운드로 전환될 때 (스트리밍 중이면 서버 유지)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: UIApplication.didEnterBackgroundNotification
                    )
                ) { _ in
                    // BackgroundAudioManager가 이미 실행 중이면 아무 것도 하지 않음
                    // 스트리밍 중이 아니면 굳이 백그라운드 유지할 필요 없음
                    if !viewModel.isStreaming {
                        BackgroundAudioManager.shared.stop()
                    }
                }
        }
    }
}
