import XCTest
@testable import TinySpectrum

final class FrequencyAxisTests: XCTestCase {
    func testAdaptiveStepsReachRequestedZoomDetail() {
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...474_000_000), 1_000_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_400_000), 100_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_200_000), 50_000)
        XCTAssertEqual(FrequencyAxis.tickStep(for: 470_000_000...470_100_000), 25_000)
    }

    func testLabelsAddOnlyNeededMHzPrecision() {
        XCTAssertEqual(FrequencyAxis.label(470_000_000, step: 1_000_000), "470 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_100_000, step: 100_000), "470.100 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_050_000, step: 50_000), "470.050 MHz")
        XCTAssertEqual(FrequencyAxis.label(470_025_000, step: 25_000), "470.025 MHz")
    }

    func testTicksAlignToStepWhilePanned() {
        XCTAssertEqual(
            FrequencyAxis.ticks(for: 470_012_000...470_112_000, step: 25_000),
            [470_025_000, 470_050_000, 470_075_000, 470_100_000]
        )
    }
}
