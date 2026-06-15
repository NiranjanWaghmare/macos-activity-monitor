import SwiftUI

/// A filled history graph (like the CPU/Network/Disk graphs in the footer).
/// Values are normalized against `maxValue`, or against the running max when
/// `maxValue` is nil (used for throughput graphs with no fixed ceiling).
struct AreaGraph: View {
    var values: [Double]
    var color: Color
    var maxValue: Double?

    var body: some View {
        GeometryReader { geo in
            let ceiling = (maxValue ?? max(values.max() ?? 1, 1))
            let w = geo.size.width
            let h = geo.size.height
            let count = max(values.count, 1)
            let step = w / CGFloat(max(count - 1, 1))

            ZStack {
                // Faint grid lines for the classic Activity Monitor look.
                Path { p in
                    for i in 1..<4 {
                        let y = h * CGFloat(i) / 4
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)

                let points = values.enumerated().map { idx, v -> CGPoint in
                    let x = CGFloat(idx) * step
                    let y = h - CGFloat(min(max(v / ceiling, 0), 1)) * h
                    return CGPoint(x: x, y: y)
                }

                // Filled area
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: h))
                    p.addLine(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                    if let last = points.last {
                        p.addLine(to: CGPoint(x: last.x, y: h))
                    }
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.05)],
                                     startPoint: .top, endPoint: .bottom))

                // Top stroke
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, lineWidth: 1.5)
            }
        }
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Per-core busy bars, mimicking the CPU history strip.
struct CoreBars: View {
    var cores: [Double]  // each 0...1

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, value in
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(barColor(value))
                            .frame(height: max(2, geo.size.height * CGFloat(value)))
                    }
                }
                .frame(width: 10)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    private func barColor(_ v: Double) -> Color {
        switch v {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
}

/// The colored Memory Pressure bar (green → yellow → red).
struct PressureBar: View {
    var fraction: Double  // 0...1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 14)
    }

    private var color: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
}

/// A labelled metric used throughout the footers.
struct StatBlock: View {
    var label: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(minWidth: 84, alignment: .leading)
    }
}

/// Small color swatch + label, used for graph legends.
struct LegendDot: View {
    var color: Color
    var text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
