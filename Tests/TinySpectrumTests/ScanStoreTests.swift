import XCTest
@testable import TinySpectrum

final class ScanStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ScanStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ScanStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = ScanStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAFreshInstallReportsNoStoreSoBuiltInPresetsSurvive() throws {
        XCTAssertNil(try store.load())
    }

    func testSingleScanRoundTrips() throws {
        let only = capture(secondsFromStart: 0, levels: [-80, -70])
        let scan = makeScan(captures: [only], continuous: false)
        try store.startSession(scan.id, firstCapture: only)
        try store.saveIndex(scans: [scan], presets: [])

        let contents = try XCTUnwrap(try store.load())

        XCTAssertEqual(contents.scans.count, 1)
        XCTAssertNil(contents.scans[0].captures, "a single scan must not come back as a continuous session")
        XCTAssertEqual(contents.scans[0].points.map(\.level), [-80, -70])
        XCTAssertNil(contents.recoveryNote)
    }

    func testContinuousSweepsAppendAndReloadInOrder() throws {
        let id = UUID()
        let first = capture(secondsFromStart: 0, levels: [-90, -90])
        try store.startSession(id, firstCapture: first)
        try store.append(capture(secondsFromStart: 1, levels: [-80, -85]), to: id)
        try store.append(capture(secondsFromStart: 2, levels: [-70, -95]), to: id)
        try store.saveIndex(scans: [makeScan(id: id, captures: [first], continuous: true)], presets: [])

        let contents = try XCTUnwrap(try store.load())
        let reloaded = try XCTUnwrap(contents.scans.first)

        XCTAssertEqual(reloaded.captureCount, 3)
        XCTAssertEqual(reloaded.captures?.map { $0.points[0].level }, [-90, -80, -70])
        // `points` is the newest sweep, which is what the graph draws live.
        XCTAssertEqual(reloaded.points.map(\.level), [-70, -95])
        XCTAssertEqual(reloaded.peakHoldPoints.map(\.level), [-70, -85])
    }

    func testACrashPartwayThroughASweepKeepsEveryCompleteCapture() throws {
        let id = UUID()
        try store.startSession(id, firstCapture: capture(secondsFromStart: 0, levels: [-80, -80]))
        try store.append(capture(secondsFromStart: 1, levels: [-75, -75]), to: id)
        try store.saveIndex(scans: [makeScan(id: id, captures: [], continuous: true)], presets: [])

        // What a crash mid-append leaves behind: a final line that never
        // finished being written.
        let session = directory.appending(path: "sessions/\(id.uuidString).ndjson")
        let handle = try FileHandle(forWritingTo: session)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"date":123456,"points":[{"frequ"#.utf8))
        try handle.close()

        let contents = try XCTUnwrap(try store.load())

        XCTAssertEqual(contents.scans.first?.captureCount, 2, "complete captures must survive the truncated tail")
        XCTAssertNotNil(contents.recoveryNote, "recovery has to be visible, not silent")
    }

    func testAStoreWrittenBeforeVersion3IsMigratedAndBackedUp() throws {
        let continuous = makeScan(
            captures: [capture(secondsFromStart: 0, levels: [-80, -70]), capture(secondsFromStart: 5, levels: [-60, -95])],
            continuous: true
        )
        let single = makeScan(captures: [capture(secondsFromStart: 0, levels: [-50, -40])], continuous: false)
        let legacy = LegacyStore(
            scans: [continuous, single],
            presets: [ScanPreset(id: UUID(), name: "FM Broadcast", startHz: 87_500_000, stopHz: 108_000_000)]
        )
        try JSONEncoder().encode(legacy).write(to: directory.appending(path: "scans.json"))

        let contents = try XCTUnwrap(try store.load())

        XCTAssertEqual(contents.scans.count, 2)
        XCTAssertEqual(contents.presets.first?.name, "FM Broadcast")
        XCTAssertNil(contents.presets.first?.rbw, "a pre-3.0 preset carries no measurement")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.appending(path: "scans-v1-backup.json").path),
            "the pre-3.0 file holds measurements that cannot be recaptured"
        )

        // Reading again must go down the migrated path and return the same library.
        let second = try XCTUnwrap(try store.load())
        XCTAssertEqual(second.scans.count, 2)
        XCTAssertEqual(second.scans.first { $0.isContinuous }?.captureCount, 2)
        XCTAssertNil(second.scans.first { !$0.isContinuous }?.captures)
    }

    func testAnUnreadableStoreIsSetAsideRatherThanDiscarded() throws {
        let index = directory.appending(path: "scans.json")
        try Data("this is not the file you are looking for".utf8).write(to: index)

        XCTAssertThrowsError(try store.load())

        XCTAssertFalse(FileManager.default.fileExists(atPath: index.path))
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("scans-unreadable-") }
        XCTAssertEqual(kept.count, 1, "the damaged file must still be on disk for the user to recover")
    }

    func testDeletingAScanRemovesItsCaptures() throws {
        let id = UUID()
        try store.startSession(id, firstCapture: capture(secondsFromStart: 0, levels: [-80, -70]))
        let session = directory.appending(path: "sessions/\(id.uuidString).ndjson")
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.path))

        store.deleteSessions([id])

        XCTAssertFalse(FileManager.default.fileExists(atPath: session.path))
    }

    // MARK: - Helpers

    private struct LegacyStore: Codable {
        var scans: [SpectrumScan]
        var presets: [ScanPreset]
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func capture(secondsFromStart: TimeInterval, levels: [Double]) -> ScanCapture {
        ScanCapture(
            date: start.addingTimeInterval(secondsFromStart),
            points: levels.enumerated().map { ScanPoint(frequency: 100_000 + Double($0.offset) * 25_000, level: $0.element) }
        )
    }

    private func makeScan(id: UUID = UUID(), captures: [ScanCapture], continuous: Bool) -> SpectrumScan {
        SpectrumScan(
            id: id,
            date: start,
            startHz: 100_000,
            stopHz: 150_000,
            rbw: "30 kHz",
            points: captures.last?.points ?? [],
            captures: continuous ? captures : nil
        )
    }
}
