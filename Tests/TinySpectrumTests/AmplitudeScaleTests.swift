import XCTest
@testable import TinySpectrum

final class AmplitudeScaleTests: XCTestCase {
    func testTheDefaultReproducesTheFixedWindowUsedBeforeVersion3() {
        XCTAssertEqual(AmplitudeScale.default.maximum, -20)
        XCTAssertEqual(AmplitudeScale.default.minimum, -120)
    }

    func testFittingTightensAroundAQuietSpan() {
        let scale = AmplitudeScale.fitting(levels: [-50, -47, -45])

        XCTAssertEqual(scale.referenceLevel, -40)
        XCTAssertEqual(scale.range, 40)
        XCTAssertGreaterThanOrEqual(scale.maximum, -45)
        XCTAssertLessThanOrEqual(scale.minimum, -50)
    }

    func testFittingRaisesTheReferenceForStrongSignals() {
        let scale = AmplitudeScale.fitting(levels: [-100, -80, -5])

        XCTAssertEqual(scale.referenceLevel, 0)
        XCTAssertGreaterThanOrEqual(scale.maximum, -5)
        XCTAssertLessThanOrEqual(scale.minimum, -100)
    }

    func testFittingOnlyEverPicksValuesTheControlsOffer() {
        for spread in stride(from: -130.0, through: 0.0, by: 7.5) {
            let scale = AmplitudeScale.fitting(levels: [spread - 30, spread])

            XCTAssertTrue(
                AmplitudeScale.referenceLevels.contains(scale.referenceLevel),
                "reference \(scale.referenceLevel) is not offered by the picker"
            )
            XCTAssertTrue(
                AmplitudeScale.ranges.contains(scale.range),
                "range \(scale.range) is not offered by the picker"
            )
        }
    }

    func testFittingCoversTheDataWheneverTheOfferedValuesCan() {
        for spread in stride(from: -110.0, through: -20.0, by: 5.0) {
            let levels = [spread - 25, spread - 10, spread]
            let scale = AmplitudeScale.fitting(levels: levels)

            XCTAssertGreaterThanOrEqual(scale.maximum, levels.max()!, "strongest sample fell above the graph")
            XCTAssertLessThanOrEqual(scale.minimum, levels.min()!, "weakest sample fell below the graph")
        }
    }

    func testFittingDegradesToTheWidestOfferedScaleRatherThanFailing() {
        // Beyond anything the pickers can express. The scale has to stay valid;
        // the graph flags the samples it cannot show.
        let scale = AmplitudeScale.fitting(levels: [-140, 25])

        XCTAssertEqual(scale.referenceLevel, 0)
        XCTAssertEqual(scale.range, 120)
    }

    func testFittingNothingLeavesTheScaleAlone() {
        XCTAssertEqual(AmplitudeScale.fitting(levels: []), .default)
    }
}
