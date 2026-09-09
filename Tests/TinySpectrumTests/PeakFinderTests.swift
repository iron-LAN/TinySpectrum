import XCTest
@testable import TinySpectrum

final class PeakFinderTests: XCTestCase {
    func testStrongestSignalsComeFirst() {
        let peaks = PeakFinder.peaks(in: trace(peakedAt: [(10, -30), (40, -50), (70, -20)]))

        XCTAssertEqual(peaks.map(\.level), [-20, -30, -50])
        XCTAssertEqual(peaks.map(\.frequency), [70_000_000, 10_000_000, 40_000_000])
    }

    func testOneBroadCarrierYieldsOnePeakNotItsShoulders() {
        // A carrier several samples wide. A naive local-maximum search reports
        // every ripple along its skirt, which is what makes such a list useless.
        var levels = [Double](repeating: -100, count: 101)
        for offset in -6...6 {
            levels[50 + offset] = -30 - Double(abs(offset)) * 2
        }
        let peaks = PeakFinder.peaks(in: trace(levels: levels))

        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks.first?.frequency, 50_000_000)
        XCTAssertEqual(peaks.first?.level, -30)
    }

    func testTwoCarriersFurtherApartThanTheSpacingAreBothReported() {
        var levels = [Double](repeating: -100, count: 101)
        levels[20] = -40
        levels[80] = -35

        let peaks = PeakFinder.peaks(in: trace(levels: levels))

        XCTAssertEqual(peaks.count, 2)
        XCTAssertEqual(Set(peaks.map(\.frequency)), [20_000_000, 80_000_000])
    }

    func testAFlatTopContributesASinglePeak() {
        var levels = [Double](repeating: -100, count: 51)
        for index in 24...28 { levels[index] = -40 }

        let peaks = PeakFinder.peaks(in: trace(levels: levels))

        XCTAssertEqual(peaks.count, 1, "a plateau must not report one peak per sample across it")
    }

    func testTheLimitIsRespected() {
        var levels = [Double](repeating: -100, count: 401)
        for carrier in 0..<20 {
            levels[10 + carrier * 20] = -30 - Double(carrier)
        }

        let peaks = PeakFinder.peaks(in: trace(levels: levels), limit: 5, minimumSpacingHz: 1_000_000)

        XCTAssertEqual(peaks.count, 5)
        XCTAssertEqual(peaks.map(\.level), [-30, -31, -32, -33, -34], "the limit must keep the strongest, not the first")
    }

    func testNoiseWithoutStructureReportsNothingSurprising() {
        let peaks = PeakFinder.peaks(in: trace(levels: [Double](repeating: -100, count: 60)))

        XCTAssertTrue(peaks.isEmpty, "a flat trace has no distinct signals")
    }

    func testTooFewSamplesToJudge() {
        XCTAssertTrue(PeakFinder.peaks(in: []).isEmpty)
        XCTAssertTrue(PeakFinder.peaks(in: trace(levels: [-50, -20])).isEmpty)
    }

    func testEdgeSamplesAreNotTreatedAsPeaks() {
        // The first and last sample have only one neighbour, so a rising edge
        // at the boundary says nothing about a signal being present.
        let peaks = PeakFinder.peaks(in: trace(levels: [-20, -100, -100, -100, -20]))

        XCTAssertTrue(peaks.isEmpty)
    }

    // MARK: - Helpers

    /// One sample per MHz starting at 0 Hz.
    private func trace(levels: [Double]) -> [ScanPoint] {
        levels.enumerated().map { ScanPoint(frequency: Double($0.offset) * 1_000_000, level: $0.element) }
    }

    private func trace(peakedAt carriers: [(index: Int, level: Double)]) -> [ScanPoint] {
        var levels = [Double](repeating: -100, count: 101)
        for carrier in carriers { levels[carrier.index] = carrier.level }
        return trace(levels: levels)
    }
}
