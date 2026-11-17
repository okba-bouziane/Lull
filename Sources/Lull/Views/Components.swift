import SwiftUI
import LullCore

enum Route { case main, freeUp, settings }

extension Color {
    static let brand = Color.indigo
}

extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

/// Small area chart of recent values.
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(pts) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 1))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 1))
                }
                .stroke(tint.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1, maxValue > 0 else { return [] }
        // Always span the full width so the chart reads the same while history fills up.
        let step = size.width / CGFloat(max(values.count - 1, 1))
        return values.enumerated().map { i, v in
            let y = size.height - 1 - CGFloat(min(v, maxValue) / maxValue) * (size.height - 3)
            return CGPoint(x: CGFloat(i) * step, y: y)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let detail: String
    let values: [Double]
    let maxValue: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(detail).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Sparkline(values: values, maxValue: maxValue, tint: tint).frame(height: 26)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}

struct NavHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack {
                Button(action: back) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
    }
}

struct AppIconView: View {
    let group: AppGroup
    var size: CGFloat = 26

    var body: some View {
        Image(nsImage: IconCache.icon(for: group))
            .resizable().interpolation(.high)
            .frame(width: size, height: size)
    }
}
