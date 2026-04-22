import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TViewModel
    /// cameraDataUpdater는 let 상수라 $viewModel 바인딩 불가 → 직접 ObservedObject로 관찰
    @ObservedObject private var cameraUpdater: CameraDataUpdater

    init(viewModel: TViewModel) {
        self.viewModel = viewModel
        self._cameraUpdater = ObservedObject(wrappedValue: viewModel.cameraDataUpdater)
    }

    var body: some View {
        NavigationStack {
            List {
                // 일반
                Section("일반") {
                    NavigationLink {
                        ThemePickerView(selection: $viewModel.theme)
                    } label: {
                        Label("테마 설정", systemImage: "paintbrush")
                    }
                    
                    Label("이용 상태", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                
                // 스트리밍
                Section("스트리밍") {
                    Picker("스트리밍 품질", selection: $viewModel.streamingQuality) {
                        ForEach(StreamingQuality.allCases, id: \.self) { q in
                            Text(q.pickerLabel).tag(q)
                        }
                    }
                    // 현재 선택값 상세 정보
                    HStack {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(viewModel.streamingQuality.resolutionDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color(.systemGray6))
                    
                    Picker("Tesla 하드웨어", selection: $viewModel.teslaHardware) {
                        Text("자동").tag(TeslaHardware.auto)
                        Text("MCU2").tag(TeslaHardware.mcu2)
                        Text("MCU3").tag(TeslaHardware.mcu3)
                    }
                    
                    Toggle("VPN IP 적용", isOn: $viewModel.useVPNIP)
                }
                
                // 절전
                Section("절전") {
                    Toggle("절전 모드", isOn: $viewModel.batterySaverMode)
                    Toggle("발열 관리", isOn: $viewModel.thermalManagement)
                    Toggle("가변 FPS", isOn: $viewModel.variableFPS)
                }
                
                // 안전
                Section("안전") {
                    Toggle("세이프 드라이빙 가드", isOn: $viewModel.safeDrivingGuardEnabled)
                }

                // 단속 카메라 데이터
                Section {
                    // 현황
                    HStack {
                        Label("카메라 수", systemImage: "camera.fill")
                        Spacer()
                        Text("\(cameraUpdater.cameraCount)개")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("마지막 업데이트", systemImage: "clock")
                        Spacer()
                        Group {
                            if let date = cameraUpdater.lastUpdated {
                                Text(date, style: .date)
                            } else {
                                Text("없음")
                            }
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }

                    // 업데이트 버튼
                    Button {
                        cameraUpdater.download(
                            into: viewModel.safeDrivingGuard.cameraManager
                        )
                    } label: {
                        HStack {
                            if cameraUpdater.isDownloading {
                                ProgressView().controlSize(.small).padding(.trailing, 4)
                            }
                            Text(cameraUpdater.isDownloading ? "다운로드 중..." : "지금 업데이트")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .disabled(cameraUpdater.isDownloading || cameraUpdater.downloadURL.isEmpty)

                    // 상태 메시지
                    if !cameraUpdater.statusMessage.isEmpty {
                        Text(cameraUpdater.statusMessage)
                            .font(.caption)
                            .foregroundStyle(
                                cameraUpdater.statusMessage.hasPrefix("✅") ? Color.green : Color.red
                            )
                    }

                    // 데이터 소스 URL (고급 — 별도 화면에서 수정)
                    NavigationLink {
                        CameraURLEditorView(cameraUpdater: cameraUpdater)
                    } label: {
                        Label("데이터 소스 경로 (고급)", systemImage: "link")
                    }
                } header: {
                    Text("단속 카메라 데이터")
                } footer: {
                    Text("공공데이터포털(data.go.kr) → \"도로교통공단 고정식단속카메라\" 변환 JSON URL을 고급 설정에 입력 후 업데이트하세요.")
                }
                .onAppear {
                    cameraUpdater.refreshCount()
                }

                // 자동화
                Section {
                    Toggle(isOn: $viewModel.autoStartEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("앱 실행 시 자동 캐스팅")
                            Text("앱을 열면 캐스팅이 바로 시작됩니다")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ShortcutsGuideView()
                    } label: {
                        Label("Shortcuts 자동화 설정", systemImage: "wand.and.stars")
                    }
                } header: {
                    Text("자동화")
                } footer: {
                    Text("Shortcuts 자동화를 설정하면 차량 블루투스 연결 시 자동으로 캐스팅을 시작할 수 있습니다.")
                }

                // 기타
                Section("기타") {
                    NavigationLink {
                        LanguagePickerView(selection: $viewModel.language)
                    } label: {
                        Label("언어 설정", systemImage: "globe")
                    }

                    Button("설정 초기화", role: .destructive) {
                        viewModel.resetSettings()
                    }
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 데이터 소스 URL 편집 화면

struct CameraURLEditorView: View {
    @ObservedObject var cameraUpdater: CameraDataUpdater
    @Environment(\.dismiss) private var dismiss
    @State private var editingURL = ""
    @State private var isEditing = false

    /// URL을 "https://abc...eras.json" 형태로 축약
    private var maskedURL: String {
        let url = cameraUpdater.downloadURL
        guard url.count > 36 else { return url }
        let prefix = String(url.prefix(18))
        let suffix = String(url.suffix(12))
        return "\(prefix)...\(suffix)"
    }

    var body: some View {
        List {
            // 현재 경로 (축약 표시)
            Section {
                HStack {
                    Text(maskedURL)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(isEditing ? "취소" : "변경") {
                        if isEditing {
                            isEditing = false
                            editingURL = ""
                        } else {
                            editingURL = ""
                            isEditing = true
                        }
                    }
                    .font(.footnote)
                }
            } header: {
                Text("현재 경로")
            }

            // 새 URL 입력 (편집 모드일 때만 표시)
            if isEditing {
                Section {
                    TextField("https://example.com/SpeedCameras.json",
                              text: $editingURL)
                        .font(.footnote)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit {
                            applyIfValid()
                        }

                    Button("적용") {
                        applyIfValid()
                    }
                    .disabled(editingURL.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("새 URL 입력")
                } footer: {
                    Text("SpeedCameras.json 형식의 URL을 입력 후 적용하세요.")
                }
            }

            Section {
                Button("기본값으로 초기화") {
                    cameraUpdater.downloadURL = CameraDataUpdater.defaultURL
                    isEditing = false
                    editingURL = ""
                }
                .foregroundStyle(.red)
            } footer: {
                Text("기본값: GitHub 저장소의 공공데이터 기반 카메라 데이터")
            }
        }
        .navigationTitle("데이터 소스 경로")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func applyIfValid() {
        let trimmed = editingURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        cameraUpdater.downloadURL = trimmed
        isEditing = false
        editingURL = ""
    }
}

// MARK: - Shortcuts 안내 화면

struct ShortcutsGuideView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("한 번 설정하면 차에 탈 때마다 자동으로 캐스팅이 시작됩니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("설정 방법") {
                stepRow(number: 1,
                        title: "단축어 앱 열기",
                        detail: "iPhone에서 단축어(Shortcuts) 앱 실행")
                stepRow(number: 2,
                        title: "자동화 탭 선택",
                        detail: "하단 '자동화' 탭 탭하기")
                stepRow(number: 3,
                        title: "새 자동화 만들기",
                        detail: "오른쪽 상단 '+' 버튼 탭하기")
                stepRow(number: 4,
                        title: "트리거 선택",
                        detail: "'블루투스' → 차량 블루투스 기기 선택 → '연결됨' 선택")
                stepRow(number: 5,
                        title: "동작 추가",
                        detail: "'동작 추가' → 'TView 캐스팅 시작' 검색 → 선택")
                stepRow(number: 6,
                        title: "저장",
                        detail: "오른쪽 상단 '완료' 탭하기")
            }

            Section("효과") {
                Label("차량 블루투스 연결 → TView 자동 실행 + 캐스팅 시작", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("Tesla 북마크만 탭하면 바로 미러링 시작", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Label("폰 화면 안 봐도 자동화 완료", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Section("Tesla 북마크 저장 (최초 1회)") {
                stepRow(number: 1,
                        title: "Tesla 브라우저 열기",
                        detail: "차량 화면에서 브라우저 아이콘 탭")
                stepRow(number: 2,
                        title: "URL 입력",
                        detail: "http://172.20.10.1:8080 입력 후 이동")
                stepRow(number: 3,
                        title: "북마크 저장",
                        detail: "주소창 옆 별표(★) 탭하여 즐겨찾기 저장")
                stepRow(number: 4,
                        title: "다음부터",
                        detail: "북마크 탭 한 번으로 바로 연결")
            }
        }
        .navigationTitle("Shortcuts 자동화")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.15))
                .clipShape(Circle())
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ThemePickerView: View {
    @Binding var selection: AppTheme
    var body: some View {
        List {
            Picker("테마", selection: $selection) {
                Text("시스템").tag(AppTheme.system)
                Text("라이트").tag(AppTheme.light)
                Text("다크").tag(AppTheme.dark)
            }
        }
        .navigationTitle("테마 설정")
    }
}

struct LanguagePickerView: View {
    @Binding var selection: AppLanguage
    var body: some View {
        List {
            Section {
                Picker("언어", selection: $selection) {
                    Text("시스템").tag(AppLanguage.system)
                    Text("한국어").tag(AppLanguage.korean)
                    Text("English").tag(AppLanguage.english)
                }
            } footer: {
                Text("현재 한국어만 완전히 지원됩니다. 선택값은 저장되며 향후 다국어 업데이트에 반영됩니다.")
            }
        }
        .navigationTitle("언어 설정")
    }
}