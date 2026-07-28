import XCTest
@testable import TinySpectrum

final class FrequencyAxisTests: XCTestCase {
    func testAdaptiveStepsReachRequestedZoomDetail() {
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...474_000_000), 1_000_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_400_000), 100_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_200_000), 50_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_100_000), 25_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_040_000), 25_000)
    }

    func testLabelsAddOnlyNeededMHzPrecision() {
        XCTAssertEqual(FrequencyAxis.label(470_000_000, step: 1_000_000), "470.000 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_100_000, step: 100_000), "470.100 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_050_000, step: 50_000), "470.050 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_025_000, step: 25_000), "470.025 MHz")
    }

    func testLabelsSwitchToGHzForGHzScans() {
        XCTAssertEqual(FrequencyAxis.label(2_400_000_000, step: 100_000_000), "2.400 GHz")
        XCTAssertEqual(FrequencyAxis.label(2_400_025_000, step: 25_000), "2.400025 GHz")
    }

    func testTicksAlignToStepWhilePanned() {
        XCTAssertEqual(
            FrequencyAxis.ticks(for: 470_012_000...470_112_000, step: 25_000),
            [470_025_000, 470_050_000, 470_075_000, 470_100_000]
        )
    }

    func testAxisAlwaysIncludesExactScanEdges() {
        let range = 470_125_000.0...474_875_000.0
        let step = FrequencyAxis.tickStep(for: range, plotWidth: 600)
        let values = FrequencyAxis.labelValues(for: range, plotWidth: 600, step: step)

        XCTAssertEqual(values.first, range.lowerBound)
        XCTAssertEqual(values.last, range.upperBound)
        XCTAssertGreaterThanOrEqual(values.count, 4)
    }

    func testAxisLabelsNeverUseLessThanMinimumSpacing() {
        let range = 100_000_000.0...800_000_000.0
        let width = 520.0
        let step = FrequencyAxis.tickStep(for: range, plotWidth: width)
        let values = FrequencyAxis.labelValues(for: range, plotWidth: width, step: step)
        let pixelPositions = values.map { ($0 - range.lowerBound) / (range.upperBound - range.lowerBound) * width }

        for pair in zip(pixelPositions, pixelPositions.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 100)
        }
    }
}
