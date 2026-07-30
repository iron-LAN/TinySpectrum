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
    var customName: String? = nil
    var rangeTitle: String { "\(Self.short(startHz)) – \(Self.short(stopHz))" }
    var title: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? rangeTitle : trimmed
    }
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

struct TinySAProfile: Equatable {
    let isUltra: Bool
    let name: String
    let maximumHz: Double
    var maximumPoints: Int { isUltra ? 450 : 290 }
    static let regular = TinySAProfile(isUltra: false, name: "tinySA Basic", maximumHz: 960_000_000)
    static let ultra = TinySAProfile(isUltra: true, name: "tinySA Ultra ZS405", maximumHz: 6_000_000_000)
    static let ultraPlusZS406 = TinySAProfile(isUltra: true, name: "tinySA Ultra+ ZS406", maximumHz: 6_000_000_000)
    static let ultraPlusZS407 = TinySAProfile(isUltra: true, name: "tinySA Ultra+ ZS407", maximumHz: 7_300_000_000)
    static func from(info: String) -> TinySAProfile {
        let text = info.lowercased()
        if text.contains("zs407") || text.contains("v0.5.3") { return .ultraPlusZS407 }
        if text.contains("zs406") || text.contains("v0.4.6") || text.contains("ultra+") { return .ultraPlusZS406 }
        return text.contains("ultra") || text.contains("tinysa4") ? .ultra : .regular
    }
    func supports(_ rbw: RBW) -> Bool { isUltra || (3_000...600_000).contains(rbw.bandwidthHz) }
    func inputMode(startHz: Double, stopHz: Double) throws -> String? {
        if isUltra { return nil }
        if startHz >= 100_000, stopHz <= 350_000_000 { return "low" }
        if startHz >= 240_000_000, stopHz <= 960_000_000 { return "high" }
        throw SerialError.unsupportedRange("A tinySA Basic scan must fit entirely in LOW input (0.1–350 MHz) or HIGH input (240–960 MHz).")
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
    // Keep these values and their order aligned with Windows ScanPalette.
    private static let darkModeColors: [Color] = [
        Color(red: 0x19 / 255, green: 0xD9 / 255, blue: 0xFF / 255),
        Color(red: 0xFF / 255, green: 0x8C / 255, blue: 0x24 / 255),
        Color(red: 0xB0 / 255, green: 0x5C / 255, blue: 0xFF / 255),
        Color(red: 0x32 / 255, green: 0xE3 / 255, blue: 0x8A / 255),
        Color(red: 0xFF / 255, green: 0x4D / 255, blue: 0x9D / 255),
        Color(red: 0xF5 / 255, green: 0xD6 / 255, blue: 0x2E / 255),
        Color(red: 0x5E / 255, green: 0x8B / 255, blue: 0xFF / 255),
        Color(red: 0x25 / 255, green: 0xE6 / 255, blue: 0xC8 / 255),
        Color(red: 0xFF / 255, green: 0x5B / 255, blue: 0x5B / 255),
        Color(red: 0xA8 / 255, green: 0xE0 / 255, blue: 0x63 / 255),
        Color(red: 0xFF / 255, green: 0x74 / 255, blue: 0xE8 / 255),
        Color(red: 0x66 / 255, green: 0xC2 / 255, blue: 0xFF / 255)
    ]
    private static let lightModeColors: [Color] = [
        Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0x99 / 255),
        Color(red: 0xB8 / 255, green: 0x4A / 255, blue: 0x00 / 255),
        Color(red: 0x6B / 255, green: 0x2A / 255, blue: 0xA6 / 255),
        Color(red: 0x08 / 255, green: 0x7A / 255, blue: 0x45 / 255),
        Color(red: 0xA8 / 255, green: 0x0D / 255, blue: 0x55 / 255),
        Color(red: 0x8A / 255, green: 0x6A / 255, blue: 0x00 / 255),
        Color(red: 0x26 / 255, green: 0x4F / 255, blue: 0xA8 / 255),
        Color(red: 0x00 / 255, green: 0x76 / 255, blue: 0x6A / 255),
        Color(red: 0xB3 / 255, green: 0x26 / 255, blue: 0x26 / 255),
        Color(red: 0x4F / 255, green: 0x7A / 255, blue: 0x12 / 255),
        Color(red: 0x8A / 255, green: 0x2C / 255, blue: 0x87 / 255),
        Color(red: 0x28 / 255, green: 0x6A / 255, blue: 0x91 / 255)
    ]
    static let count = darkModeColors.count
    static func color(_ index: Int, scheme: ColorScheme) -> Color {
        let colors = scheme == .dark ? darkModeColors : lightModeColors
        return colors[index % colors.count]
    }
}
