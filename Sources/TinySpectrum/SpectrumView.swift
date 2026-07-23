import SwiftUI

private struct HoverSample {
    let point: ScanPoint
    let color: Color
    let location: CGPoint
}

struct SpectrumView: View {
    @Environment(\.colorScheme) private var colorScheme
    let scans: [SpectrumScan]
    let selected: Set<UUID>
    let timelinePosition: Double
    let timelineCaptureIndex: Int?
    @State private var hover: HoverSample?

    var visible: [(Int, SpectrumScan)] { scans.enumerated().filter { selected.contains($0.element.id) } }
    private var allPoints: [ScanPoint] { visible.flatMap { $0.1.points(atCaptureIndex: timelineCaptureIndex) } }

    var body: some View {
        GeometryReader { geo in
            let plot = plotRect(geo.size)
            let bounds = dataBounds
            Canvas { context, _ in
                let plotBackground = colorScheme == .dark ? Color(red: 0.025, green: 0.055, blue: 0.075) : Color(red: 0.94, green: 0.97, blue: 0.98)
                context.fill(Path(roundedRect: plot, cornerRadius: 8), with: .color(plotBackground))
                drawGrid(context: context, plot: plot)
                labels(context: context, plot: plot, bounds: bounds)
                guard !visible.isEmpty else { return }
                for (index, scan) in visible {
                    var path = Path()
                    for (i, point) in scan.points(atCaptureIndex: timelineCaptureIndex).enumerated() {
                        let location = screenLocation(point, plot: plot, bounds: bounds)
                        if i == 0 { path.move(to: location) } else { path.addLine(to: location) }
                    }
                    context.stroke(path, with: .color(Palette.color(index, scheme: colorScheme)), lineWidth: 1.8)
                }
                if let hover {
                    var vertical = Path(); vertical.move(to: .init(x: hover.location.x, y: plot.minY)); vertical.addLine(to: .init(x: hover.location.x, y: plot.maxY))
                    context.stroke(vertical, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    context.fill(Path(ellipseIn: CGRect(x: hover.location.x - 4, y: hover.location.y - 4, width: 8, height: 8)), with: .color(hover.color))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover = nearestSample(to: location, plot: plot, bounds: bounds)
                case .ended: hover = nil
                }
            }
            .overlay(alignment: .top) {
                if let hover {
                    HStack(spacing: 16) {
                        Label(SpectrumScan.short(hover.point.frequency), systemImage: "waveform")
                        Text(String(format: "%.2f dBm", hover.point.level))
                    }
                    .font(.caption.monospacedDigit().bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(hover.color.opacity(0.8), lineWidth: 1))
                    .padding(.top, 4)
                }
            }
            .overlay {
                if visible.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text("Select a scan or start a new one").foregroundStyle(.secondary)
                    }.offset(y: 12)
                }
            }
        }
    }

    private var dataBounds: (minF: Double, maxF: Double, minL: Double, maxL: Double) {
        guard let minF = allPoints.map(\.frequency).min(), let maxF = allPoints.map(\.frequency).max(), maxF > minF else {
            return (0, 1, -120, -20)
        }
        return (minF, maxF, -120, -20)
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: 68, y: 42, width: max(1, size.width - 88), height: max(1, size.height - 84))
    }

    private func screenLocation(_ point: ScanPoint, plot: CGRect, bounds: (minF: Double, maxF: Double, minL: Double, maxL: Double)) -> CGPoint {
        let y = plot.maxY - (point.level - bounds.minL) / (bounds.maxL - bounds.minL) * plot.height
        return .init(x: plot.minX + (point.frequency - bounds.minF) / (bounds.maxF - bounds.minF) * plot.width,
                     y: min(plot.maxY, max(plot.minY, y)))
    }

    private func nearestSample(to cursor: CGPoint, plot: CGRect, bounds: (minF: Double, maxF: Double, minL: Double, maxL: Double)) -> HoverSample? {
        guard plot.contains(cursor) else { return nil }
        var result: HoverSample?, bestDistance = Double.greatestFiniteMagnitude
        for (index, scan) in visible {
            for point in scan.points(atCaptureIndex: timelineCaptureIndex) {
                let location = screenLocation(point, plot: plot, bounds: bounds)
                let distance = hypot(location.x - cursor.x, location.y - cursor.y)
                if distance < bestDistance {
                    bestDistance = distance
                    result = HoverSample(point: point, color: Palette.color(index, scheme: colorScheme), location: location)
                }
            }
        }
        return result
    }

    private func drawGrid(context: GraphicsContext, plot: CGRect) {
        for i in 0...10 {
            let x = plot.minX + Double(i) / 10 * plot.width
            var p = Path(); p.move(to: .init(x: x, y: plot.minY)); p.addLine(to: .init(x: x, y: plot.maxY))
            let grid = colorScheme == .dark ? Color.white : Color(red: 0.08, green: 0.25, blue: 0.32)
            context.stroke(p, with: .color(grid.opacity(i == 0 || i == 10 ? 0.22 : 0.10)), lineWidth: 1)
        }
        for i in 0...5 {
            let y = plot.minY + Double(i) / 5 * plot.height
            var p = Path(); p.move(to: .init(x: plot.minX, y: y)); p.addLine(to: .init(x: plot.maxX, y: y))
            let grid = colorScheme == .dark ? Color.white : Color(red: 0.08, green: 0.25, blue: 0.32)
            context.stroke(p, with: .color(grid.opacity(i == 0 || i == 5 ? 0.22 : 0.10)), lineWidth: 1)
        }
    }

    private func labels(context: GraphicsContext, plot: CGRect, bounds: (minF: Double, maxF: Double, minL: Double, maxL: Double)) {
        if !visible.isEmpty {
            for i in 0...4 {
                let t = Double(i) / 4
                context.draw(Text(SpectrumScan.short(bounds.minF + (bounds.maxF - bounds.minF) * t)).font(.caption2).foregroundColor(.secondary), at: .init(x: plot.minX + t * plot.width, y: plot.maxY + 17), anchor: .center)
            }
        }
        for i in 0...5 {
            let t = Double(i) / 5
            let value = bounds.maxL - (bounds.maxL - bounds.minL) * t
            context.draw(Text(String(format: "%.0f", value)).font(.caption.monospacedDigit()).foregroundColor(.secondary), at: .init(x: plot.minX - 10, y: plot.minY + t * plot.height), anchor: .trailing)
        }
        context.draw(Text("dBm").font(.caption2.bold()).foregroundColor(.secondary), at: .init(x: plot.minX - 30, y: plot.minY - 14), anchor: .center)
    }
}
