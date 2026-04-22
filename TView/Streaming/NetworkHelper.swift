import Foundation
import Darwin

/// 네트워크 인터페이스 IP 주소 감지 유틸리티
enum NetworkHelper {

    /// Tesla 브라우저에서 접속할 IP 기반 URL
    static func streamingURL(useVPN: Bool = false) -> String {
        "http://\(streamingIP(useVPN: useVPN)):\(StreamingServer.port)"
    }

    /// mDNS 기반 로컬 URL (DeviceName.local:8080)
    /// - Tesla 브라우저(Chromium)에서 mDNS 주소 지원
    static func localURL() -> String {
        "http://\(StreamingServer.localHostname):\(StreamingServer.port)"
    }

    /// 현재 활성 네트워크 인터페이스에서 IP 주소 반환
    static func streamingIP(useVPN: Bool = false) -> String {
        // VPN 모드: utun 인터페이스에서 IP 탐색 (WireGuard, OpenVPN 등)
        if useVPN {
            for i in 0...4 {
                if let ip = ipAddress(for: "utun\(i)") {
                    return ip
                }
            }
        }
        // Personal Hotspot 인터페이스 우선 (bridge100) → 항상 172.20.10.1
        if let ip = ipAddress(for: "bridge100") { return ip }
        // Wi-Fi (en0)
        if let ip = ipAddress(for: "en0") { return ip }
        // 시뮬레이터 / 기타 Wi-Fi
        if let ip = ipAddress(for: "en1") { return ip }
        // Personal Hotspot 기본 IP
        return "172.20.10.1"
    }

    /// 특정 네트워크 인터페이스의 IPv4 주소 반환
    static func ipAddress(for interfaceName: String) -> String? {
        var result: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let name = String(cString: current.pointee.ifa_name)
            guard name == interfaceName else { continue }
            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let addrLen = socklen_t(current.pointee.ifa_addr.pointee.sa_len)
            let ret = getnameinfo(
                current.pointee.ifa_addr,
                addrLen,
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )
            if ret == 0 {
                result = String(cString: hostname)
                break
            }
        }
        return result
    }
}
