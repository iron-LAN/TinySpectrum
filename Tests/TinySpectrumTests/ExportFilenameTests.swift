import XCTest
@testable import TinySpectrum

final class ExportFilenameTests: XCTestCase {
    func testScanFilenameUsesCaptureDateAndLocation() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-26T18:30:00Z"))

        XCTAssertEqual(
            ExportFilename.baseName(date: date, location: "Ziggo Dome, Amsterdam", timeZone: TimeZone(secondsFromGMT: 0)!),
            "26-07-26_Ziggo-Dome-Amsterdam_"
        )
    }

    func testTimelineFilenameUsesUnknownLocationFallback() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-26T18:30:00Z"))

        XCTAssertEqual(
            ExportFilename.baseName(date: date, location: nil, timeZone: TimeZone(secondsFromGMT: 0)!),
            "26-07-26_UnknownLocation_"
        )
    }
}
