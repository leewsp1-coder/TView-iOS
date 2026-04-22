import Foundation

/// 단속 카메라 데이터를 원격 URL에서 다운로드하고 앱에 즉시 적용하는 클래스
@MainActor
class CameraDataUpdater: ObservableObject {

    @Published var isDownloading = false
    @Published var statusMessage = ""
    @Published var lastUpdated: Date? = nil
    @Published var cameraCount = 0

    @Published var downloadURL: String = "" {
        didSet { UserDefaults.standard.set(downloadURL, forKey: UDKey.url) }
    }

    private enum UDKey {
        static let url  = "tv.cameraDataURL"
        static let date = "tv.cameraDataLastUpdated"
    }

    /// GitHub 저장소의 SpeedCameras.json raw URL (GitHub Actions가 매월 자동 갱신)
    static let defaultURL = "https://raw.githubusercontent.com/leewsp1-coder/TView-iOS/main/TView/Resources/SpeedCameras.json"

    init() {
        // 저장된 URL이 없으면 기본 GitHub URL로 초기화
        let saved = UserDefaults.standard.string(forKey: UDKey.url) ?? ""
        downloadURL = saved.isEmpty ? Self.defaultURL : saved
        if let ts = UserDefaults.standard.object(forKey: UDKey.date) as? Double, ts > 0 {
            lastUpdated = Date(timeIntervalSince1970: ts)
        }
        refreshCount()
    }

    // MARK: - 카메라 수 동기화

    /// 현재 저장된 파일(Documents > 번들 순)에서 카메라 수를 읽어 갱신
    func refreshCount() {
        struct Root: Decodable { let cameras: [SpeedCamera] }

        guard let documentsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let docsURL = documentsDir.appendingPathComponent("SpeedCameras.json")

        if let data = try? Data(contentsOf: docsURL),
           let root = try? JSONDecoder().decode(Root.self, from: data) {
            cameraCount = root.cameras.count
            return
        }

        if let bundleURL = Bundle.main.url(forResource: "SpeedCameras", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let root = try? JSONDecoder().decode(Root.self, from: data) {
            cameraCount = root.cameras.count
        }
    }

    // MARK: - 다운로드

    func download(into manager: SpeedCameraManager) {
        let trimmed = downloadURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            statusMessage = "URL을 입력해주세요."
            return
        }
        guard let url = URL(string: trimmed) else {
            statusMessage = "유효하지 않은 URL입니다."
            return
        }

        isDownloading = true
        statusMessage = "다운로드 중..."

        Task {
            defer { isDownloading = false }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    statusMessage = "서버 오류 (HTTP \(http.statusCode))"
                    return
                }

                // 형식 검증
                struct Root: Decodable { let cameras: [SpeedCamera] }
                let root: Root
                do {
                    root = try JSONDecoder().decode(Root.self, from: data)
                } catch {
                    statusMessage = "형식 오류: JSON 구조를 확인해주세요"
                    return
                }

                guard !root.cameras.isEmpty else {
                    statusMessage = "카메라 데이터가 비어 있습니다."
                    return
                }
                guard root.cameras.count <= 100_000 else {
                    statusMessage = "데이터 오류: 카메라 수 초과 (\(root.cameras.count)개)"
                    return
                }

                // Documents에 저장 (앱 재시작 후에도 유지)
                guard let documentsDir = FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask).first else {
                    statusMessage = "저장 경로를 찾을 수 없습니다."
                    return
                }
                let docsURL = documentsDir.appendingPathComponent("SpeedCameras.json")
                try data.write(to: docsURL)

                // 실행 중인 매니저 즉시 갱신
                manager.reload(cameras: root.cameras)

                cameraCount = root.cameras.count
                lastUpdated = Date()
                UserDefaults.standard.set(lastUpdated!.timeIntervalSince1970, forKey: UDKey.date)
                statusMessage = "✅ \(root.cameras.count)개 카메라 업데이트 완료"

            } catch let urlError as URLError {
                statusMessage = "네트워크 오류: \(urlError.localizedDescription)"
            } catch {
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
    }
}
