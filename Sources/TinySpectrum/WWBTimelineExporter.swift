import Foundation

enum WWBTimelineExporter {
    enum ExportError: LocalizedError {
        case notContinuous
        case noSamples
        case spanTooNarrow

        var errorDescription: String? {
            switch self {
            case .notContinuous: "Only continuous scans can be exported as a WWB timeline."
            case .noSamples: "The continuous scan does not contain any samples."
            case .spanTooNarrow: "Wireless Workbench requires a frequency span of at least 25 kHz."
            }
        }
    }

    private struct Grid {
        let startKHz: Int
        let stopKHz: Int
        let stepKHz: Int

        var count: Int { (stopKHz - startKHz) / stepKHz + 1 }
        var recordSize: Int { 4 + 4 + 4 + count * 2 + 2 }
    }

    static func data(for scan: SpectrumScan, title: String) throws -> Data {
        guard let captures = scan.captures else { throw ExportError.notContinuous }
        guard let first = captures.first, first.points.count >= 2 else { throw ExportError.noSamples }
        let grid = try makeGrid(from: first.points)
        let safeTitle = title.isEmpty ? "TinySpectrum continuous scan" : title

        func curve(name: String, color: String) -> [String: Any] {
            [
                "Color": color,
                "CoordinationSource": true,
                "FreqRanges": [[
                    "EndFreq": grid.stopKHz,
                    "StartFreq": grid.startKHz,
                    "StepFreq": grid.stepKHz
                ]],
                "Name": name,
                "ResolutionBandWidth": resolutionBandwidthKHz(scan.rbw)
            ]
        }
        let header: [String: Any] = [
            "AmplUnits": "dBm",
            "BinarySchema": [
                ["Bytes": 4, "DataValue": "start-of-sweep"],
                ["Bytes": 4, "DataValue": "id"],
                ["Bytes": 4, "DataValue": "timestamp"],
                ["Curve": curve(name: "Antenna A", color: "#ffff00")],
                ["Bytes": 2, "DataValue": "crc16"]
            ],
            "BitWidth": 16,
            "FreqUnits": "KHz",
            "NoDataValue": -1400,
            "PeriodicSpecialSweeps": [
                ["Interval": 40, "Type": "Periodic running peakhold"],
                ["Interval": 100, "Type": "Periodic interval peakhold"]
            ],
            "Scale Factor": 10,
            "ScannerModel": "",
            "ScannerName": "AD600",
            "StartDate": dateString(first.date),
            "StartTime": timeString(first.date),
            "Title": safeTitle,
            "Version": "1.0.0.0"
        ]

        var output = Data("//@ShureScan\n".utf8)
        output.append(try JSONSerialization.data(withJSONObject: header, options: [.prettyPrinted, .sortedKeys]))
        output.append(Data("\n@Binary:".utf8))

        var runningPeak = [Int16](repeating: -1400, count: grid.count)
        var intervalPeak = [Int16](repeating: -1400, count: grid.count)
        var totalRecords: UInt32 = 0
        let startDate = first.date

        for (offset, capture) in captures.enumerated() {
            let samples = resample(capture.points, onto: grid)
            mergePeak(samples, into: &runningPeak)
            mergePeak(samples, into: &intervalPeak)
            let identifier = UInt32(offset + 1)
            let elapsed = max(0, capture.date.timeIntervalSince(startDate).rounded())
            output.append(record(id: identifier, timestamp: UInt32(clamping: Int(elapsed)), samples: samples))
            totalRecords += 1

            if identifier.isMultiple(of: 40) {
                output.append(record(id: 0, timestamp: 0, samples: runningPeak))
                totalRecords += 1
            }
            if identifier.isMultiple(of: 100) {
                output.append(record(id: 0, timestamp: 0, samples: intervalPeak))
                totalRecords += 1
                intervalPeak = [Int16](repeating: -1400, count: grid.count)
            }
        }

        let extended: [String: Any] = [
            "Band": "Wideband",
            "Creator": "TinySpectrum 2.0.1-beta.2",
            "ScanName": [safeTitle],
            "UserCurveColors": ["#ffff00"]
        ]
        output.append(Data("@Extended:\n".utf8))
        output.append(try JSONSerialization.data(withJSONObject: extended, options: [.prettyPrinted, .sortedKeys]))
        output.append(0x0A)
        output.append(Data(repeating: 0x20, count: max(0, grid.recordSize - 6)))
        output.append(0x0A)
        output.append(Data("@End".utf8))
        output.appendBigEndian(UInt32(captures.count))
        output.appendBigEndian(totalRecords)
        return output
    }

    private static func makeGrid(from points: [ScanPoint]) throws -> Grid {
        let sorted = points.sorted { $0.frequency < $1.frequency }
        guard let first = sorted.first, let last = sorted.last else { throw ExportError.noSamples }
        let startKHz = Int(ceil(first.frequency / 1_000))
        let availableStopKHz = Int(floor(last.frequency / 1_000))
        guard availableStopKHz - startKHz >= 25 else { throw ExportError.spanTooNarrow }
        let sourceStepKHz = (last.frequency - first.frequency) / Double(max(1, sorted.count - 1)) / 1_000
        let stepKHz = max(25, Int(sourceStepKHz.rounded()))
        let count = max(2, (availableStopKHz - startKHz) / stepKHz + 1)
        return Grid(startKHz: startKHz, stopKHz: startKHz + (count - 1) * stepKHz, stepKHz: stepKHz)
    }

    private static func resample(_ points: [ScanPoint], onto grid: Grid) -> [Int16] {
        let sorted = points.sorted { $0.frequency < $1.frequency }
        guard sorted.count >= 2 else { return [Int16](repeating: -1400, count: grid.count) }
        var result: [Int16] = []
        result.reserveCapacity(grid.count)
        var upperIndex = 1
        for index in 0..<grid.count {
            let frequency = Double(grid.startKHz + index * grid.stepKHz) * 1_000
            while upperIndex < sorted.count - 1, sorted[upperIndex].frequency < frequency { upperIndex += 1 }
            let lower = sorted[upperIndex - 1]
            let upper = sorted[upperIndex]
            guard frequency >= lower.frequency, frequency <= upper.frequency else {
                result.append(-1400)
                continue
            }
            let span = max(1, upper.frequency - lower.frequency)
            let fraction = (frequency - lower.frequency) / span
            let level = lower.level + (upper.level - lower.level) * fraction
            result.append(Int16(clamping: Int((level * 10).rounded())))
        }
        return result
    }

    private static func mergePeak(_ samples: [Int16], into peak: inout [Int16]) {
        for index in samples.indices where samples[index] != -1400 {
            peak[index] = max(peak[index], samples[index])
        }
    }

    private static func record(id: UInt32, timestamp: UInt32, samples: [Int16]) -> Data {
        var value = Data("@Swp".utf8)
        value.appendBigEndian(id)
        value.appendBigEndian(timestamp)
        for sample in samples { value.appendBigEndian(sample) }
        value.appendBigEndian(crc16ARC(value))
        return value
    }

    private static func crc16ARC(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }

    private static func resolutionBandwidthKHz(_ label: String) -> Double {
        let number = Scanner(string: label).scanDouble() ?? 30
        return label.lowercased().contains("khz") ? number : number / 1_000
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
