import SwiftUI
import ReplayKit

struct MainView: View {
    @ObservedObject var viewModel: TViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // 상단: 스트리밍 상태 + 속도
                    statusBar

                    // Tesla 화면 미리보기 (항상 표시, 스트리밍 중엔 실시간 데이터 반영)
                    TeslaPreviewCard(viewModel: viewModel)

                    // 스트리밍 중: 연결 정보 (URL)
                    if viewModel.isStreaming {
                        connectionInfoCard
                        broadcastCard
                    }

                    // 스트리밍 품질 선택
                    qualityPicker

                    // 캐스팅 시작/중지 버튼
                    castButton

                    // 오류 메시지
                    if let error = viewModel.errorMessage {
                        errorBanner(message: error)
                    }

                    // 사용 안내 (스트리밍 중일 때)
                    if viewModel.isStreaming {
                        instructionCard
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .navigationTitle("TView")
            .navigationBarTitleDisplayMode(.inline)
        }
        // HUD 데이터 주기적 동기화 (1초 간격 — GPS 업데이트 주기와 일치)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            viewModel.syncHUDToServer()
        }
    }

    // MARK: - 하위 뷰

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.streamingState.color)
                .frame(width: 10, height: 10)
            Text(viewModel.streamingState.text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // 주행 중 표시
            if viewModel.safeDrivingGuard.isDriving {
                Label("\(Int(viewModel.safeDrivingGuard.speed)) km/h", systemImage: "car.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
    }

    private var previewPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "car.top.radiowaves.rear")
                        .font(.system(size: 56))
                        .foregroundStyle(.gray)
                    Text("Tesla 미리보기")
                        .foregroundStyle(.gray)
                    Text("캐스팅 시작 후 Tesla 브라우저에서\n아래 URL로 접속하세요")
                        .font(.caption)
                        .foregroundStyle(.gray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(height: 220)
            .padding(.horizontal)
    }

    private var connectionInfoCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(.green)
                Text("스트리밍 중")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
            }

            Divider()

            // URL 표시
            VStack(alignment: .leading, spacing: 8) {
                Text("Tesla 브라우저에서 접속")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // IP 주소 URL
                urlRow(label: "IP", url: viewModel.serverURL)

                // mDNS .local URL (더 기억하기 쉬운 주소)
                if !viewModel.localURL.isEmpty {
                    urlRow(label: "로컬", url: viewModel.localURL)
                }
            }

            // 세이프 드라이빙 가드 상태
            if viewModel.safeDrivingGuardEnabled {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.safeDrivingGuard.isDriving
                          ? "lock.fill" : "lock.open")
                        .foregroundStyle(viewModel.safeDrivingGuard.isDriving ? .orange : .green)
                    Text(viewModel.safeDrivingGuard.isDriving
                         ? "주행 중 - 화면 잠금 중"
                         : "세이프 가드 활성")
                        .font(.caption)
                        .foregroundStyle(viewModel.safeDrivingGuard.isDriving ? .orange : .secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("스트리밍 품질")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Picker("품질", selection: $viewModel.streamingQuality) {
                ForEach(StreamingQuality.allCases, id: \.self) { q in
                    Text(q.pickerLabel).tag(q)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // 현재 선택된 품질의 해상도/FPS 상세 설명
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(viewModel.streamingQuality.resolutionDetail)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 2)
        }
    }

    private var castButton: some View {
        Button {
            viewModel.toggleStreaming()
        } label: {
            HStack {
                Image(systemName: viewModel.isStreaming ? "stop.fill" : "play.fill")
                Text(viewModel.isStreaming ? "캐스팅 중지" : "캐스팅 시작")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.isStreaming ? Color.red : Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }

    /// 화면 브로드캐스트 시작 카드 (RPSystemBroadcastPickerView 포함)
    private var broadcastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.purple)
                Text("전체 화면 미러링")
                    .font(.headline)
                Spacer()
            }

            Text("아래 버튼을 탭해 iPhone 전체 화면 공유를 시작하세요. 다른 앱도 미러링됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                BroadcastPickerView(preferredExtension: "com.tview.app.broadcast")
                    .frame(width: 60, height: 60)
                Spacer()
            }

            Text("공유 중지: 상태바의 빨간 녹화 아이콘 탭 → 중지")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private var instructionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("연결 방법", systemImage: "questionmark.circle")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                instructionStep(number: 1, text: "iPhone 개인 핫스팟을 켜세요")
                instructionStep(number: 2, text: "Tesla에서 iPhone 핫스팟에 연결하세요")
                instructionStep(number: 3, text: "위 '전체 화면 미러링' 버튼으로 화면 공유 시작")
                instructionStep(number: 4, text: "Tesla 브라우저에서 위 URL을 입력하세요")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func urlRow(label: String, url: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            Text(url)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            Button {
                UIPasteboard.general.string = url
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Color.blue.opacity(0.2))
                .clipShape(Circle())
                .foregroundStyle(.blue)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}

// MARK: - RPSystemBroadcastPickerView 래퍼

/// iOS 시스템 브로드캐스트 픽커를 SwiftUI에서 사용하기 위한 래퍼
struct BroadcastPickerView: UIViewRepresentable {
    let preferredExtension: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    MainView(viewModel: TViewModel())
}
