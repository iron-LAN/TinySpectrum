import Foundation
import SwiftUI

struct ScanPoint: Codable, Hashable { let frequency: Double; let level: Double }

struct ScanCapture: Codable, Hashable {
    let date: Date
    let points: [ScanPoint]
}

struct SpectrumScan: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let startHz: Double
    let stopHz: Double
    let rbw: String
    var points: [ScanPoint]
    var captures: [ScanCapture]?
    var title: String { "\(Self.short(startHz)) – \(Self.short(stopHz))" }
    var captureCount: Int { captures?.count ?? 1 }
    var isContinuous: Bool { captures != nil }
    var peakHoldPoints: [ScanPoint] { peakHoldPoints(atCaptureIndex: nil) }
    func peakHoldPoints(atCaptureIndex index: Int?) -> [ScanPoint] {
        guard let captures, let first = captures.first else { return points }
        let lastIndex = min(captures.count - 1, max(0, index ?? captures.count - 1))
        var peak = first.points
        for capture in captures.prefix(lastIndex + 1).dropFirst() {
            for index in 0..<min(peak.count, capture.points.count) {
                guard abs(peak[index].frequency - capture.points[index].frequency) < 1 else { continue }
                if capture.points[index].level > peak[index].level { peak[index] = capture.points[index] }
            }
        }
        return peak
    }
    func points(at timelinePosition: Double) -> [ScanPoint] {
        guard let captures, !captures.isEmpty else { return points }
        let index = min(captures.count - 1, max(0, Int((timelinePosition * Double(captures.count - 1)).rounded())))
        return captures[index].points
    }
    func points(atCaptureIndex index: Int?) -> [ScanPoint] {
        guard let captures, !captures.isEmpty else { return points }
        guard let index else { return captures.last!.points }
        return captures[min(captures.count - 1, max(0, index))].points
    }
    func captureDate(atCaptureIndex index: Int?) -> Date {
        guard let captures, !captures.isEmpty else { return date }
        guard let index else { return captures.last!.date }
        return captures[min(captures.count - 1, max(0, index))].date
    }
    func captureDate(at timelinePosition: Double) -> Date {
        guard let captures, !captures.isEmpty else { return date }
        let index = min(captures.count - 1, max(0, Int((timelinePosition * Double(captures.count - 1)).rounded())))
        return captures[index].date
    }
    static func short(_ hz: Double) -> String {
        if hz >= 1e9 { return String(format: "%.3g GHz", hz / 1e9) }
        if hz >= 1e6 { return String(format: "%.3g MHz", hz / 1e6) }
        if hz >= 1e3 { return String(format: "%.3g kHz", hz / 1e3) }
        return String(format: "%.0f Hz", hz)
    }
}

struct ScanPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var startHz: Double
    var stopHz: Double
}

enum RBW: String, CaseIterable, Identifiable {
    case hz200 = "200 Hz", khz1 = "1 kHz", khz3 = "3 kHz"
    case khz10 = "10 kHz", khz30 = "30 kHz (AD600 scan)", khz100 = "100 kHz"
    case khz300 = "300 kHz (AD600 live)", khz600 = "600 kHz", khz850 = "850 kHz"
    var id: String { rawValue }
    var bandwidthHz: Double {
        switch self {
        case .hz200: 200
        case .khz1: 1_000
        case .khz3: 3_000
        case .khz10: 10_000
        case .khz30: 30_000
        case .khz100: 100_000
        case .khz300: 300_000
        case .khz600: 600_000
        case .khz850: 850_000
        }
    }
    var command: String {
        switch self {
        case .hz200: "0.2"
        case .khz1: "1"
        case .khz3: "3"
        case .khz10: "10"
        case .khz30: "30"
        case .khz100: "100"
        case .khz300: "300"
        case .khz600: "600"
        case .khz850: "850"
        }
    }
}

enum ScanInterval: Int, CaseIterable, Identifiable {
    case seconds10 = 10
    case seconds30 = 30
    case minute1 = 60
    case minutes5 = 300
    case minutes10 = 600
    case minutes30 = 1_800

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String {
        switch self {
        case .seconds10: "10s"
        case .seconds30: "30s"
        case .minute1: "1m"
        case .minutes5: "5m"
        case .minutes10: "10m"
        case .minutes30: "30m"
        }
    }
}

enum SweepEstimator {
    static func duration(spanHz: Double, rbw: RBW, outputPoints: Int = 145) -> TimeInterval {
        // tinySA may insert measurement steps when the requested RBW is
        // narrower than the output-point spacing. Settling time also grows as
        // RBW narrows. These conservative values follow that device behavior.
        let settlingTime: TimeInterval = switch rbw {
        case .hz200: 0.040
        case .khz1: 0.015
        case .khz3: 0.006
        case .khz10: 0.0034
        case .khz30: 0.0018
        case .khz100: 0.0010
        case .khz300: 0.0007
        case .khz600: 0.0006
        case .khz850: 0.00055
        }
        let coverageStep = rbw.bandwidthHz * 0.8
        let measurementSteps = max(Double(outputPoints), ceil(max(1, spanHz) / coverageStep))
        return 0.35 + measurementSteps * settlingTime
    }

    static func finestRBW(spanHz: Double, fitting interval: ScanInterval) -> RBW {
        RBW.allCases.first { duration(spanHz: spanHz, rbw: $0) <= interval.seconds } ?? .khz850
    }

    static func shortestInterval(spanHz: Double, fitting rbw: RBW) -> ScanInterval {
        let estimate = duration(spanHz: spanHz, rbw: rbw)
        return ScanInterval.allCases.first { estimate <= $0.seconds } ?? .minutes30
    }
}

enum Palette {
    private static let darkColors: [Color] = [
        Color(red: 0.10, green: 0.86, blue: 1.00),
        Color(red: 1.00, green: 0.55, blue: 0.14),
        Color(red: 0.72, green: 0.34, blue: 1.00),
        Color(red: 0.20, green: 0.95, blue: 0.55),
        Color(red: 1.00, green: 0.25, blue: 0.67),
        Color(red: 0.98, green: 0.86, blue: 0.18),
        Color(red: 0.25, green: 0.48, blue: 1.00),
        Color(red: 0.15, green: 0.90, blue: 0.78),
        Color(red: 1.00, green: 0.28, blue: 0.30)
    ]
    private static let lightColors: [Color] = [
        Color(red: 0.00, green: 0.42, blue: 0.58),
        Color(red: 0.72, green: 0.29, blue: 0.00),
        Color(red: 0.43, green: 0.12, blue: 0.68),
        Color(red: 0.00, green: 0.48, blue: 0.23),
        Color(red: 0.68, green: 0.05, blue: 0.38),
        Color(red: 0.58, green: 0.46, blue: 0.00),
        Color(red: 0.08, green: 0.25, blue: 0.68),
        Color(red: 0.00, green: 0.48, blue: 0.40),
        Color(red: 0.72, green: 0.08, blue: 0.10)
    ]
    static let count = darkColors.count
    static func color(_ index: Int, scheme: ColorScheme) -> Color {
        let colors = scheme == .dark ? darkColors : lightColors
        return colors[index % colors.count]
    }
}
