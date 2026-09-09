import XCTest
@testable import TinySpectrum

final class TraceModeTests: XCTestCase {
    func testAverageIsTheMeanUpToTheTimelinePosition() {
        let scan = continuousScan()

        XCTAssertEqual(scan.averagePoints(atCaptureIndex: 0).map(\.level), [-80, -70])
        XCTAssertEqual(scan.averagePoints(atCaptureIndex: 1).map(\.level), [-85, -65])
        XCTAssertEqual(scan.averagePoints(atCaptureIndex: 2).map(\.level), [-80, -60])
    }

    func testAverageAndMaxHoldDisagreeAsTheyShould() {
        let scan = continuousScan(mode: .maxHold)

        XCTAssertEqual(scan.peakHoldPoints(atCaptureIndex: 2).map(\.level), [-70, -50])
        XCTAssertEqual(scan.averagePoints(atCaptureIndex: 2).map(\.level), [-80, -60])
    }

    func testLiveDrawsNoOverlay() {
        XCTAssertNil(continuousScan(mode: .live).overlayPoints(atCaptureIndex: nil))
    }

    func testEachModeSelectsItsOwnOverlay() {
        XCTAssertEqual(
            continuousScan(mode: .maxHold).overlayPoints(atCaptureIndex: 2)?.map(\.level),
            [-70, -50]
        )
        XCTAssertEqual(
            continuousScan(mode: .average).overlayPoints(atCaptureIndex: 2)?.map(\.level),
            [-80, -60]
        )
    }

    func testASingleSweepHasNothingToAccumulate() {
        let single = SpectrumScan(
            id: UUID(),
            date: Date(),
            startHz: 100_000,
            stopHz: 150_000,
            rbw: "30 kHz",
            points: [ScanPoint(frequency: 100_000, level: -80)],
            captures: nil,
            traceMode: .maxHold
        )

        XCTAssertNil(single.overlayPoints(atCaptureIndex: nil), "a single scan must never draw an accumulated trace")
    }

    func testTraceModeStaysOutOfTheScanEncodingSoOldStoresStillMigrate() throws {
        let scan = continuousScan(mode: .average)

        let json = String(decoding: try JSONEncoder().encode(scan), as: UTF8.self)
        XCTAssertFalse(json.contains("traceMode"), "display state must not enter the measurement encoding")

        // A pre-3.0 scan carries no trace mode and has to decode regardless.
        let decoded = try JSONDecoder().decode(SpectrumScan.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.traceMode, .live)
    }

    func testTraceModeSurvivesAStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "TraceModeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScanStore(directory: directory)

        let scan = continuousScan(mode: .average)
        try store.startSession(scan.id, firstCapture: scan.captures![0])
        try store.append(scan.captures![1], to: scan.id)
        try store.append(scan.captures![2], to: scan.id)
        try store.saveIndex(scans: [scan], presets: [])

        let reloaded = try XCTUnwrap(try store.load()).scans.first

        XCTAssertEqual(reloaded?.traceMode, .average)
        XCTAssertEqual(reloaded?.overlayPoints(atCaptureIndex: 2)?.map(\.level), [-80, -60])
    }

    // MARK: - Helpers

    private func continuousScan(mode: TraceMode = .live) -> SpectrumScan {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let captures = [
            capture(start, [-80, -70]),
            capture(start.addingTimeInterval(1), [-90, -60]),
            capture(start.addingTimeInterval(2), [-70, -50])
        ]
        return SpectrumScan(
            id: UUID(),
            date: start,
            startHz: 100_000,
            stopHz: 125_000,
            rbw: "30 kHz",
            points: captures[2].points,
            captures: captures,
            traceMode: mode
        )
    }

    private func capture(_ date: Date, _ levels: [Double]) -> ScanCapture {
        ScanCapture(
            date: date,
            points: levels.enumerated().map { ScanPoint(frequency: 100_000 + Double($0.offset) * 25_000, level: $0.element) }
        )
    }
}
