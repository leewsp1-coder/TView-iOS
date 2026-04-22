import SwiftUI

/// Tesla 브라우저에서 보여질 화면을 앱 안에서 미리 보여주는 SwiftUI 모형
struct TeslaPreviewCard: View {

    @ObservedObject var viewModel: TViewModel
    /// safeDrivingGuard를 별도 관찰 → 속도/방위각/카메라 변경 시 자동 갱신
    @ObservedObject private var guard_: SafeDrivingGuard

    init(viewModel: TViewModel) {
        self.viewModel = viewModel
        self._guard_ = ObservedObject(wrappedValue: viewModel.safeDrivingGuard)
    }

    private static let compassDirs = ["북","북동","동","남동","남","남서","서","북서"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // 제목 행
            HStack {
                Label("Tesla 화면 미리보기", systemImage: "car.front.waves.up")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isStreaming {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("실시간").font(.caption2).foregroundStyle(.green)
                    }
                }
            }

            // Tesla 화면 모형 (16:9 비율)
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        hudBar
                        mirrorArea
                    }

                    // 레이아웃 버튼 (HUD 아래 우측)
                    VStack(spacing: 3) {
                        layoutBtn("전체")
                        layoutBtn("분할", active: true)
                        layoutBtn("자유")
                    }
                    .padding(.top, 50)
                    .padding(.trailing, 5)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .aspectRatio(16 / 9, contentMode: .fit)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - HUD 바

    private var hudBar: some View {
        HStack(spacing: 0) {
            speedSection
            Spacer()
            cameraSection
            Spacer()
            compassSection
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(Color.black.opacity(0.90))
        .overlay(
            Rectangle().frame(height: 0.5).foregroundStyle(.white.opacity(0.10)),
            alignment: .bottom
        )
    }

    private var speedSection: some View {
        let spd = Int(guard_.speed)
        let overLimit = viewModel.isStreaming
            && guard_.cameraAlertLevel != .none
            && guard_.speed > Double(guard_.cameraSpeedLimit)

        return HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(spd > 0 ? "\(spd)" : "--")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(overLimit ? .red : .white)
                .animation(.easeInOut(duration: 0.3), value: overLimit)
            Text("km/h")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(width: 72, alignment: .leading)
    }

    private var cameraSection: some View {
        Group {
            if viewModel.isStreaming && guard_.cameraAlertLevel != .none {
                let dist = Int(guard_.cameraDistance)
                let distStr = dist >= 1000
                    ? String(format: "%.1fkm", Double(dist) / 1000)
                    : "\(dist)m"
                let badgeText = "📷 \(guard_.cameraType)  \(guard_.cameraSpeedLimit)km/h  \(distStr)"

                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(cameraAlertBg)
                    .foregroundStyle(cameraAlertFg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(cameraAlertFg.opacity(0.4), lineWidth: 0.5))
            } else {
                Text("단속 카메라 없음")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }

    private var cameraAlertBg: Color {
        switch guard_.cameraAlertLevel {
        case .caution: return Color.yellow.opacity(0.18)
        case .warning: return Color.orange.opacity(0.18)
        case .alert:   return Color.red.opacity(0.22)
        case .none:    return .clear
        }
    }

    private var cameraAlertFg: Color {
        switch guard_.cameraAlertLevel {
        case .caution: return .yellow
        case .warning: return .orange
        case .alert:   return .red
        case .none:    return .white
        }
    }

    private var compassSection: some View {
        let hdg = guard_.heading
        let dir = viewModel.isStreaming
            ? Self.compassDirs[((Int((hdg / 45).rounded()) % 8) + 8) % 8]
            : "--"

        return VStack(spacing: 1) {
            Text(viewModel.isStreaming ? "\(Int(hdg))°" : "--")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
            Text(dir)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(width: 40, alignment: .trailing)
    }

    // MARK: - 미러 영역

    private var mirrorArea: some View {
        ZStack {
            Color(white: 0.04)

            // 미세 격자 패턴 (화면 영역 시각화)
            gridPattern

            // 안내 텍스트
            VStack(spacing: 8) {
                Image(systemName: viewModel.isStreaming
                      ? "iphone.radiowaves.left.and.right"
                      : "iphone")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.18))
                Text(viewModel.isStreaming ? "미러링 중" : "캐스팅 시작 후 표시됩니다")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.18))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridPattern: some View {
        Canvas { context, size in
            let spacing: CGFloat = 20
            let lineColor = Color.white.opacity(0.04)
            var x: CGFloat = 0
            while x < size.width {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                    with: .color(lineColor), lineWidth: 0.5
                )
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                    with: .color(lineColor), lineWidth: 0.5
                )
                y += spacing
            }
        }
    }

    // MARK: - 레이아웃 버튼

    private func layoutBtn(_ label: String, active: Bool = false) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .medium))
            .frame(width: 28, height: 17)
            .background(active ? Color.blue.opacity(0.35) : Color.white.opacity(0.07))
            .foregroundStyle(active ? Color(red: 0.49, green: 0.82, blue: 1.0) : .white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(active ? Color.blue.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}
