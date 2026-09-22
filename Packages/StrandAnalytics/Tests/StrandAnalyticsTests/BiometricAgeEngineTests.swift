import XCTest
@testable import StrandAnalytics

final class BiometricAgeEngineTests: XCTestCase {

    private func baseInputs(hrvBaselineMean: Double? = nil, hrvBaselineSpread: Double? = nil,
                            trainingLoadRatio: Double? = nil, rmssd: Double? = nil) -> BiometricAgeEngine.Inputs {
        BiometricAgeEngine.Inputs(
            chronoAge: 30, sex: "male", restingHR: 55, paIndex: FitnessAgeEngine.paiReference,
            rmssd: rmssd, sleepHours: 7.5, sleepNeedHours: 8.0, sleepConsistency: 0.9,
            trainingLoadRatio: trainingLoadRatio, respRateCV: nil,
            hrvBaselineMean: hrvBaselineMean, hrvBaselineSpread: hrvBaselineSpread)
    }

    func testLoadRecoveryInteractionSkippedWithoutHrvBaseline() {
        let inputs = baseInputs(trainingLoadRatio: 1.6, rmssd: 40)
        let result = BiometricAgeEngine.compute(inputs)
        XCTAssertFalse(result?.contributions.contains { $0.key == "load_recovery_interaction" } ?? false)
    }

    func testHighLoadWithSuppressedHrvAddsAgingPenalty() {
        // Load well above the high-load ceiling (1.5), HRV well below personal baseline.
        let inputs = baseInputs(hrvBaselineMean: 65, hrvBaselineSpread: 8, trainingLoadRatio: 1.8, rmssd: 45)
        let result = BiometricAgeEngine.compute(inputs)
        guard let contribution = result?.contributions.first(where: { $0.key == "load_recovery_interaction" }) else {
            return XCTFail("expected a load_recovery_interaction contribution")
        }
        XCTAssertGreaterThan(contribution.deltaYears, 0)
    }

    func testHighLoadWithStrongHrvAddsSmallBonus() {
        // Load above the sweet spot, HRV comfortably above personal baseline (z > 0.5).
        let inputs = baseInputs(hrvBaselineMean: 65, hrvBaselineSpread: 8, trainingLoadRatio: 1.4, rmssd: 75)
        let result = BiometricAgeEngine.compute(inputs)
        guard let contribution = result?.contributions.first(where: { $0.key == "load_recovery_interaction" }) else {
            return XCTFail("expected a load_recovery_interaction contribution")
        }
        XCTAssertLessThan(contribution.deltaYears, 0)
        // Asymmetric by design: the bonus magnitude stays below the penalty's own cap.
        XCTAssertLessThanOrEqual(abs(contribution.deltaYears), 1.5)
    }

    func testBalancedLoadHasNoInteractionContribution() {
        // Inside the sweet spot — no interaction contribution should be added regardless of HRV.
        let inputs = baseInputs(hrvBaselineMean: 65, hrvBaselineSpread: 8, trainingLoadRatio: 1.0, rmssd: 40)
        let result = BiometricAgeEngine.compute(inputs)
        XCTAssertFalse(result?.contributions.contains { $0.key == "load_recovery_interaction" } ?? false)
    }
}
