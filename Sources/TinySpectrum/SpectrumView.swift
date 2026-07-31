import SwiftUI
import AppKit

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
    let peakHoldEnabled: Bool
    @State private var hover: HoverSample?
    @State private var frequencyWindow: ClosedRange<Double>?
    @State private var dragStartWindow: ClosedRange<Double>?

    var visible: [(Int, SpectrumScan)] { scans.enumerated().filter { selected.contains($0.element.id) } }
    private var allPoints: [ScanPoint] {
        visible.flatMap { _, scan in
            scan.points(atCaptureIndex: timelineCaptureIndex) + (peakHoldEnabled && scan.isContinuous ? scan.peakHoldPoints(atCaptureIndex: timelineCaptureIndex) : [])
        }
    }

    var body: some View {
        GeometryReader { geo in
            let plot = plotRect(geo.size)
            let bounds = dataBounds
            Canvas { context, _ in
                let plotBackground = colorScheme == .dark
                    ? Color(red: 7 / 255, green: 19 / 255, blue: 28 / 255)
                    : Color(red: 248 / 255, green: 252 / 255, blue: 253 / 255)
                context.fill(Path(roundedRect: plot, cornerRadius: 8), with: .color(plotBackground))
                drawGrid(context: context, plot: plot)
                labels(context: context, plot: plot, bounds: bounds)
                if !visible.isEmpty {
                    context.drawLayer { layer in
                        layer.clip(to: Path(roundedRect: plot, cornerRadius: 8))
                        for (index, scan) in visible {
                            var path = Path()
                            for (i, point) in scan.points(atCaptureIndex: timelineCaptureIndex).enumerated() {
                                let location = screenLocation(point, plot: plot, bounds: bounds)
                                if i == 0 { path.move(to: location) } else { path.addLine(to: location) }
                            }
                            layer.stroke(path, with: .color(Palette.color(index, scheme: colorScheme)), lineWidth: 1.8)
                            if peakHoldEnabled, scan.isContinuous {
                                var peakPath = Path()
                                for (i, point) in scan.peakHoldPoints(atCaptureIndex: timelineCaptureIndex).enumerated() {
                                    let location = screenLocation(point, plot: plot, bounds: bounds)
                                    if i == 0 { peakPath.move(to: location) } else { peakPath.addLine(to: location) }
                                }
                                layer.stroke(peakPath, with: .color(.red), lineWidth: 1.3)
                            }
                        }
                        if let hover {
                            var vertical = Path(); vertical.move(to: .init(x: hover.location.x, y: plot.minY)); vertical.addLine(to: .init(x: hover.location.x, y: plot.maxY))
                            layer.stroke(vertical, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            layer.fill(Path(ellipseIn: CGRect(x: hover.location.x - 4, y: hover.location.y - 4, width: 8, height: 8)), with: .color(hover.color))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .background {
                ScrollWheelReader { location, delta in
                    zoom(at: location, delta: delta, plot: plot)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hover = nearestSample(to: location, plot: plot, bounds: bounds)
                case .ended: hover = nil
                }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in pan(value, plot: plot) }
                    .onEnded { _ in dragStartWindow = nil }
            )
            .overlay(alignment: .top) {
                if let hover {
                    HStack(spacing: 16) {
                        Label(SpectrumScan.short(hover.point.frequency), systemImage: "waveform")
                        Text(String(format: "%.2f dBm", hover.point.level))
                    }
                    .font(.caption.monospacedDigit().bold())
                    .frame(width: 250)
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
        .onChange(of: selected) { _ in
            frequencyWindow = nil
            dragStartWindow = nil
            hover = nil
        }
    }

    private var dataBounds: (minF: Double, maxF: Double, minL: Double, maxL: Double) {
        guard let fullRange = visibleFrequencyRange else {
            return (0, 1, -120, -20)
        }
        let range = FrequencyZoom.clamped(frequencyWindow ?? fullRange, to: fullRange)
        return (range.lowerBound, range.upperBound, -120, -20)
    }

    private var visibleFrequencyRange: ClosedRange<Double>? {
        guard let minF = allPoints.map(\.frequency).min(), let maxF = allPoints.map(\.frequency).max(), maxF > minF else { return nil }
        return minF...maxF
    }

    private func zoom(at location: CGPoint, delta: CGFloat, plot: CGRect) {
        guard plot.contains(location), let fullRange = visibleFrequencyRange, delta != 0 else { return }
        let anchor = min(1, max(0, (location.x - plot.minX) / plot.width))
        let sensitivity = 0.035
        let scale = exp(-Double(delta) * sensitivity)
        frequencyWindow = FrequencyZoom.window(
            current: frequencyWindow ?? fullRange,
            full: fullRange,
            anchor: Double(anchor),
            scale: scale
        )
        hover = nil
    }

    private func pan(_ value: DragGesture.Value, plot: CGRect) {
        guard plot.contains(value.startLocation), let fullRange = visibleFrequencyRange else { return }
        let start = dragStartWindow ?? FrequencyZoom.clamped(frequencyWindow ?? fullRange, to: fullRange)
        guard start != fullRange else { return }
        if dragStartWindow == nil { dragStartWindow = start }
        frequencyWindow = FrequencyZoom.panned(
            current: start,
            full: fullRange,
            translationFraction: Double(value.translation.width / plot.width)
        )
        hover = nil
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
            for point in scan.points(atCaptureIndex: timelineCaptureIndex) where point.frequency >= bounds.minF && point.frequency <= bounds.maxF {
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
            let range = bounds.minF...bounds.maxF
            let step = FrequencyAxis.tickStep(for: range, plotWidth: plot.width)
            for frequency in FrequencyAxis.labelValues(for: range, plotWidth: plot.width, step: step) {
                let position = (frequency - bounds.minF) / (bounds.maxF - bounds.minF)
                let anchor: UnitPoint = frequency == range.lowerBound ? .leading : (frequency == range.upperBound ? .trailing : .center)
                context.draw(
                    Text(FrequencyAxis.label(frequency, step: step)).font(.caption2.monospacedDigit()).foregroundColor(.secondary),
                    at: .init(x: plot.minX + position * plot.width, y: plot.maxY + 17),
                    anchor: anchor
                )
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

enum FrequencyAxis {
    private static let minimumLabelSpacing = 100.0
    private static let minimumTickStep = 25_000.0

    static func tickStep(for range: ClosedRange<Double>, targetIntervals: Double = 4) -> Double {
        let span = max(1, range.upperBound - range.lowerBound)
        let rawStep = span / max(1, targetIntervals)
        let magnitude = pow(10, floor(log10(rawStep)))
        let normalized = rawStep / magnitude
        let multiplier = [1.0, 2.0, 2.5, 5.0, 10.0].first { $0 >= normalized } ?? 10
        return max(minimumTickStep, multiplier * magnitude)
    }

    static func tickStep(for range: ClosedRange<Double>, plotWidth: Double) -> Double {
        let intervals = max(1, floor(plotWidth / minimumLabelSpacing))
        return tickStep(for: range, targetIntervals: intervals)
    }

    static func labelValues(for range: ClosedRange<Double>, plotWidth: Double, step: Double) -> [Double] {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return [] }
        var result = [range.lowerBound]
        for value in ticks(for: range, step: step) where value > range.lowerBound && value < range.upperBound {
            let fromPrevious = (value - result.last!) / span * plotWidth
            let fromEnd = (range.upperBound - value) / span * plotWidth
            if fromPrevious >= minimumLabelSpacing, fromEnd >= minimumLabelSpacing {
                result.append(value)
            }
        }
        result.append(range.upperBound)
        return result
    }

    static func ticks(for range: ClosedRange<Double>, step: Double) -> [Double] {
        guard step > 0, range.upperBound > range.lowerBound else { return [] }
        let epsilon = step * 1e-9
        var value = ceil((range.lowerBound - epsilon) / step) * step
        var result: [Double] = []
        while value <= range.upperBound + epsilon, result.count < 12 {
            result.append(value)
            value += step
        }
        return result
    }

    static func label(_ frequency: Double, step: Double) -> String {
        let useGHz = abs(frequency) >= 1_000_000_000 || step >= 1_000_000_000
        let useMHz = !useGHz && (abs(frequency) >= 1_000_000 || step >= 1_000_000)
        let divisor = useGHz ? 1_000_000_000.0 : useMHz ? 1_000_000.0 : 1_000.0
        let unit = useGHz ? "GHz" : useMHz ? "MHz" : "kHz"
        let scaledStep = step / divisor
        let decimals = useGHz ? min(6, max(3, decimalPlaces(for: scaledStep))) : useMHz ? 3 : decimalPlaces(for: scaledStep)
        return String(format: "%.*f %@", decimals, frequency / divisor, unit)
    }

    private static func decimalPlaces(for value: Double) -> Int {
        for decimals in 0...6 {
            let scale = pow(10, Double(decimals))
            if abs(value * scale - (value * scale).rounded()) < 1e-7 { return decimals }
        }
        return 6
    }
}

enum FrequencyZoom {
    static func window(current: ClosedRange<Double>, full: ClosedRange<Double>, anchor: Double, scale: Double) -> ClosedRange<Double> {
        let fullSpan = full.upperBound - full.lowerBound
        guard fullSpan > 0 else { return full }
        let currentRange = clamped(current, to: full)
        let currentSpan = currentRange.upperBound - currentRange.lowerBound
        let minimumSpan = max(1, fullSpan / 1_000)
        let newSpan = min(fullSpan, max(minimumSpan, currentSpan * scale))
        if newSpan >= fullSpan { return full }

        let position = min(1, max(0, anchor))
        let anchorFrequency = currentRange.lowerBound + currentSpan * position
        var lower = anchorFrequency - newSpan * position
        lower = min(max(lower, full.lowerBound), full.upperBound - newSpan)
        return lower...(lower + newSpan)
    }

    static func clamped(_ range: ClosedRange<Double>, to full: ClosedRange<Double>) -> ClosedRange<Double> {
        let fullSpan = full.upperBound - full.lowerBound
        let span = min(fullSpan, max(0, range.upperBound - range.lowerBound))
        guard span < fullSpan else { return full }
        let lower = min(max(range.lowerBound, full.lowerBound), full.upperBound - span)
        return lower...(lower + span)
    }

    static func panned(current: ClosedRange<Double>, full: ClosedRange<Double>, translationFraction: Double) -> ClosedRange<Double> {
        let range = clamped(current, to: full)
        let span = range.upperBound - range.lowerBound
        guard span < full.upperBound - full.lowerBound else { return full }
        let proposedLower = range.lowerBound - translationFraction * span
        let lower = min(max(proposedLower, full.lowerBound), full.upperBound - span)
        return lower...(lower + span)
    }
}

private struct ScrollWheelReader: NSViewRepresentable {
    let onScroll: (CGPoint, CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ScrollWheelView: NSView {
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onScroll?(location, event.scrollingDeltaY)
                return event
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
