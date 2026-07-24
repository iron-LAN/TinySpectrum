import Foundation
import XCTest
@testable import TinySpectrum

final class WWBTimelineExporterTests: XCTestCase {
    func testSweepEstimatorCouplesIntervalAndResolution() {
        let span = 700_000_000.0
        XCTAssertEqual(SweepEstimator.finestRBW(spanHz: span, fitting: .seconds10), .khz100)
        XCTAssertEqual(SweepEstimator.finestRBW(spanHz: span, fitting: .minute1), .khz30)
        XCTAssertEqual(SweepEstimator.finestRBW(spanHz: span, fitting: .minutes5), .khz10)
        XCTAssertEqual(SweepEstimator.shortestInterval(spanHz: span, fitting: .khz30), .minute1)
        XCTAssertLessThan(SweepEstimator.duration(spanHz: span, rbw: .khz100), SweepEstimator.duration(spanHz: span, rbw: .khz30))
    }

    func testPeakHoldUsesHighestLevelAtEachFrequency() {
        var scan = makeScan(captureCount: 3)
        scan.captures?[1] = ScanCapture(date: scan.date.addingTimeInterval(2), points: [
            ScanPoint(frequency: 100_000, level: -90),
            ScanPoint(frequency: 125_000, level: -80),
            ScanPoint(frequency: 150_000, level: -70)
        ])
        scan.captures?[2] = ScanCapture(date: scan.date.addingTimeInterval(4), points: [
            ScanPoint(frequency: 100_000, level: -75),
            ScanPoint(frequency: 125_000, level: -85),
            ScanPoint(frequency: 150_000, level: -55)
        ])
        XCTAssertEqual(scan.peakHoldPoints.map(\.frequency), [100_000, 125_000, 150_000])
        XCTAssertEqual(scan.peakHoldPoints.map(\.level), [-75, -70, -55])
        XCTAssertEqual(scan.peakHoldPoints(atCaptureIndex: 0).map(\.level), [-80, -70, -60])
        XCTAssertEqual(scan.peakHoldPoints(atCaptureIndex: 1).map(\.level), [-80, -70, -60])
        XCTAssertEqual(scan.peakHoldPoints(atCaptureIndex: 2).map(\.level), [-75, -70, -55])
    }

    func testTimelineRecordsAndChecksumsMatchShureContainer() throws {
        let scan = makeScan(captureCount: 100)
        let data = try WWBTimelineExporter.data(for: scan, title: "Test timeline")
        let binaryMarker = try XCTUnwrap(data.range(of: Data("@Binary:".utf8)))
        let binaryStart = binaryMarker.upperBound
        let recordSize = 20 // 14 bytes of framing plus one curve with three 16-bit samples
        let expectedRecords = 103 // 100 normal, running peak hold at 40/80, interval peak hold at 100
        let extendedStart = binaryStart + expectedRecords * recordSize

        XCTAssertEqual(String(data: data[extendedStart..<(extendedStart + 10)], encoding: .utf8), "@Extended:")
        XCTAssertEqual(readUInt32(data, at: binaryStart + 4), 1)
        XCTAssertEqual(readUInt32(data, at: binaryStart + 8), 0)

        let recordAfterSweep40 = binaryStart + 40 * recordSize
        XCTAssertEqual(readUInt32(data, at: recordAfterSweep40 + 4), 0)
        XCTAssertEqual(readUInt32(data, at: recordAfterSweep40 + 8), 0)

        for recordIndex in 0..<expectedRecords {
            let start = binaryStart + recordIndex * recordSize
            let payload = data[start..<(start + recordSize - 2)]
            XCTAssertEqual(readUInt16(data, at: start + recordSize - 2), crc16ARC(payload))
        }

        let endMarker = try XCTUnwrap(data.range(of: Data("@End".utf8), options: .backwards))
        XCTAssertEqual(readUInt32(data, at: endMarker.upperBound), 100)
        XCTAssertEqual(readUInt32(data, at: endMarker.upperBound + 4), UInt32(expectedRecords))
    }

    private func makeScan(captureCount: Int) -> SpectrumScan {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let captures = (0..<captureCount).map { index in
            ScanCapture(
                date: start.addingTimeInterval(Double(index * 2)),
                points: [
                    ScanPoint(frequency: 100_000, level: -80 + Double(index % 3)),
                    ScanPoint(frequency: 125_000, level: -70 + Double(index % 3)),
                    ScanPoint(frequency: 150_000, level: -60 + Double(index % 3))
                ]
            )
        }
        return SpectrumScan(
            id: UUID(),
            date: start,
            startHz: 100_000,
            stopHz: 150_000,
            rbw: "30 kHz",
            points: captures.last!.points,
            captures: captures
        )
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<(offset + 2)].reduce(0) { ($0 << 8) | UInt16($1) }
    }

    private func crc16ARC(_ data: Data.SubSequence) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        return crc
    }
}
