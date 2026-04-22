import Foundation
import CoreLocation

/// 주행 중 스트리밍을 제한하는 안전 운전 가드
///
/// - 속도 5km/h 이상 시 주행 중으로 판단
/// - 주행 중 + 가드 활성화 시 Tesla 화면에 잠금 화면 표시
class SafeDrivingGuard: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var speed: Double = 0       // km/h
    @Published var heading: Double = 0     // 방위각 (0-360)
    @Published var isDriving: Bool = false
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // 단속 카메라 상태 (SwiftUI 뷰에서 직접 관찰 가능)
    @Published var cameraAlertLevel: CameraAlertLevel = .none
    @Published var cameraDistance: Double = .infinity
    @Published var cameraSpeedLimit: Int = 0
    @Published var cameraType: String = ""

    /// 주행 판단 최소 속도 (km/h)
    private let drivingThreshold: Double = 5.0

    private let locationManager = CLLocationManager()

    /// 과속 단속 카메라 매니저
    let cameraManager = SpeedCameraManager()

    /// 주행 상태 변경 콜백
    var onDrivingStateChanged: ((Bool) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - 모니터링 제어

    func startMonitoring() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading()
        default:
            break
        }
    }

    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        speed = 0
        heading = 0
        isDriving = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        let speedMS = max(0, location.speed) // 음수 방지
        let newSpeed = speedMS * 3.6         // m/s → km/h
        let wasDriving = isDriving

        speed = newSpeed
        isDriving = newSpeed >= drivingThreshold
        cameraManager.update(location: location)
        // @Published로 카메라 상태 동기화 → TeslaPreviewCard 자동 갱신
        cameraAlertLevel  = cameraManager.alertLevel
        cameraDistance    = cameraManager.distanceToNearest
        cameraSpeedLimit  = cameraManager.nearestCamera?.limit ?? 0
        cameraType        = cameraManager.nearestCamera?.type ?? ""

        if isDriving != wasDriving {
            onDrivingStateChanged?(isDriving)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("TView: 위치 오류 - \(error.localizedDescription)")
    }
}
