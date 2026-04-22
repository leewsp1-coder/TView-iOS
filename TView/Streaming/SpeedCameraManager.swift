import Foundation
import CoreLocation

// MARK: - 경보 수준

enum CameraAlertLevel: String {
    case none     = "none"     // 1km 이상
    case caution  = "caution"  // 500~1000m
    case warning  = "warning"  // 200~500m
    case alert    = "alert"    // 200m 미만

    var isActive: Bool { self != .none }
}

// MARK: - 과속 단속 카메라 모델

struct SpeedCamera: Decodable {
    let lat: Double
    let lng: Double
    let limit: Int     // 제한 속도 km/h
    let type: String   // 고정식, 구간단속, 이동식

    func distance(from location: CLLocation) -> Double {
        CLLocation(latitude: lat, longitude: lng).distance(from: location)
    }
}

// MARK: - 매니저

/// 번들된 SpeedCameras.json 을 기반으로 가장 가까운 단속 카메라와 거리를 계산합니다.
///
/// **실제 데이터 업데이트 방법:**
/// 공공데이터포털(data.go.kr) → 도로교통공단 고정식 단속카메라 데이터를
/// SpeedCameras.json 형식으로 변환 후 Resources 폴더에 교체하세요.
class SpeedCameraManager {

    private var cameras: [SpeedCamera] = []

    // MARK: - 현재 상태 (SafeDrivingGuard 위치 업데이트마다 갱신)
    private(set) var nearestCamera: SpeedCamera?
    private(set) var distanceToNearest: Double = .infinity
    private(set) var alertLevel: CameraAlertLevel = .none

    init() {
        loadCameras()
    }

    // MARK: - 위치 업데이트 처리

    func update(location: CLLocation) {
        let result = cameras
            .map { (cam: $0, dist: $0.distance(from: location)) }
            .filter { $0.dist < 2000 }
            .min { $0.dist < $1.dist }

        if let found = result {
            nearestCamera = found.cam
            distanceToNearest = found.dist
            alertLevel = level(for: found.dist)
        } else {
            nearestCamera = nil
            distanceToNearest = .infinity
            alertLevel = .none
        }
    }

    // MARK: - 거리 → 경보 수준 변환

    private func level(for distance: Double) -> CameraAlertLevel {
        switch distance {
        case ..<200:  return .alert
        case ..<500:  return .warning
        case ..<1000: return .caution
        default:      return .none
        }
    }

    // MARK: - 런타임 갱신

    /// 앱 내 다운로드 후 호출 — 메모리 내 목록을 즉시 교체
    func reload(cameras newCameras: [SpeedCamera]) {
        cameras = newCameras
        print("TView: 단속 카메라 \(cameras.count)개 재로드")
    }

    // MARK: - 데이터 로드

    private func loadCameras() {
        struct Root: Decodable { let cameras: [SpeedCamera] }

        // Documents 디렉토리 우선 (앱 내 다운로드 데이터)
        let docsURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SpeedCameras.json")

        if let docsURL,
           let data = try? Data(contentsOf: docsURL),
           let root = try? JSONDecoder().decode(Root.self, from: data) {
            cameras = root.cameras
            print("TView: 단속 카메라 \(cameras.count)개 로드 (다운로드 데이터)")
            return
        }

        // 번들 기본 데이터
        guard let bundleURL = Bundle.main.url(forResource: "SpeedCameras", withExtension: "json"),
              let data = try? Data(contentsOf: bundleURL),
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            print("TView: SpeedCameras.json 없음 - 과속 단속 기능 비활성")
            return
        }
        cameras = root.cameras
        print("TView: 단속 카메라 \(cameras.count)개 로드 (번들)")
    }
}
