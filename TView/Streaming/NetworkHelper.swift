import Foundation
import Darwin

/// 네트워크 인터페이스 IP 주소 감지 유틸리티
enum NetworkHelper {

    struct ConnectionURLs {
        /// 핫스팟 URL (Tesla 접속용) — 핫스팟이 켜져 있을 때만 존재
        let hotspot: String?
        /// WiFi URL — WiFi에 연결돼 있을 때만 존재
        let wifi: String?
        /// VPN URL — VPN 활성 시만 존재
        let vpn: String?

        /// Tesla 연결에 권장하는 최우선 URL
        var primary: String {
            hotspot ?? wifi ?? vpn ?? "http://172.20.10.1:\(StreamingServer.port)"
        }
    }

    /// 현재 활성 인터페이스 별 연결 URL 일괄 반환
    static func allURLs(useVPN: Bool = false) -> ConnectionURLs {
        let port = StreamingServer.port

        var vpnURL: String? = nil
        if useVPN {
            for i in 0...4 {
                if let ip = ipAddress(for: "utun\(i)") {
                    vpnURL = "http://\(ip):\(port)"; break
                }
            }
        }

        let hotspotURL = ipAddress(for: "bridge100").map { "http://\($0):\(port)" }
        let wifiURL    = (ipAddress(for: "en0") ?? ipAddress(for: "en1"))
                            .map { "http://\($0):\(port)" }

        return ConnectionURLs(hotspot: hotspotURL, wifi: wifiURL, vpn: vpnURL)
    }

    /// Tesla 브라우저에서 접속할 IP 기반 URL (기존 호환)
    static func streamingURL(useVPN: Bool = false) -> String {
        allURLs(useVPN: useVPN).primary
    }

    /// mDNS 기반 로컬 URL (DeviceName.local:8080)
    static func localURL() -> String {
        "http://\(StreamingServer.localHostname):\(StreamingServer.port)"
    }

    /// 현재 활성 네트워크 인터페이스에서 IP 주소 반환
    static func streamingIP(useVPN: Bool = false) -> String {
        allURLs(useVPN: useVPN).primary
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: ":").first ?? "172.20.10.1"
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
