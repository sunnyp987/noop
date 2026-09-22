import XCTest
@testable import StrandAnalytics

final class FitnessAgeEngineTests: XCTestCase {

    // MARK: - VO₂max estimate (Nes 2011 waist-circumference variant, confirmed coefficients)

    func testVO2maxMenKnownValue() {
        // 100.27 − 0.296·40 + 0.226·5 − 0.369·90 − 0.155·65 = 46.275
        let v = FitnessAgeEngine.estimateVO2max(age: 40, sex: "male", waistCm: 90, restingHR: 65, paIndex: 5)
        XCTAssertEqual(v, 46.275, accuracy: 1e-3)
    }

    func testVO2maxWomenKnownValue() {
        // 74.74 − 0.247·40 + 0.198·5 − 0.259·80 − 0.114·65 = 37.72
        let v = FitnessAgeEngine.estimateVO2max(age: 40, sex: "female", waistCm: 80, restingHR: 65, paIndex: 5)
        XCTAssertEqual(v, 37.72, accuracy: 1e-3)
    }

    func testBMIHelper() {
        XCTAssertEqual(FitnessAgeEngine.bmi(weightKg: 80, heightCm: 178), 25.249, accuracy: 1e-3)
    }

    // MARK: - Fitness Age (self-consistent Nes; waist cancels, so only age/sex/RHR/PA needed)

    func testFitnessAgeReferenceFitPersonEqualsChronoAge() {
        // RHR 65 + PAI 5 = the reference peer → Fitness Age == chronological age exactly.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 65, paIndex: 5),
                       40.0, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 55, sex: "female", restingHR: 65, paIndex: 5),
                       55.0, accuracy: 1e-9)
    }

    func testFitnessAgeFitterIsYounger() {
        // Man 40, RHR 50, PAI 10: 40 + (0.155·(−15) − 0.226·5)/0.296 = 28.33
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 50, paIndex: 10),
                       28.33, accuracy: 0.05)
    }

    func testFitnessAgeUnfitterIsOlder() {
        // Man 40, RHR 80, PAI 2: 40 + (0.155·15 − 0.226·(−3))/0.296 = 50.15
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 80, paIndex: 2),
                       50.15, accuracy: 0.05)
    }

    func testFitnessAgeClampsToRange() {
        // Extremely unfit, older → clamps to 80.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 75, sex: "male", restingHR: 120, paIndex: 0),
                       80, accuracy: 1e-9)
        // Extremely fit, young → clamps to 20.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 25, sex: "male", restingHR: 35, paIndex: 15),
                       20, accuracy: 1e-9)
    }

    // MARK: - PA-index reconstruction (HUNT1 PA-Q buckets)

    func testPAIndexSedentary() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 0, avgActiveMinutesPerDay: 0, highIntensityFraction: 0), 0, accuracy: 1e-9)
    }

    func testPAIndexHighlyActive() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 7, avgActiveMinutesPerDay: 75, highIntensityFraction: 0.8), 15.0, accuracy: 1e-9)
    }

    func testPAIndexModerate() {
        // 3 days (2.5) × moderate (2) × ~40 min (0.75) = 3.75
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 3, avgActiveMinutesPerDay: 40, highIntensityFraction: 0.3), 3.75, accuracy: 1e-9)
    }

    func testPAIndexFromStrain() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 0, meanActiveStrain: 0), 0, accuracy: 1e-9)
        // 7 days × strain 90 (id 3.0) = 15.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 7, meanActiveStrain: 90), 15.0, accuracy: 1e-9)
        // 3 days (freq 2.5) × strain 45 (id 1.5) = 3.75.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 3, meanActiveStrain: 45), 3.75, accuracy: 1e-9)
        // reference-ish: 4 days (2.5) × strain 60 (id 2.0) = 5.0.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 4, meanActiveStrain: 60), 5.0, accuracy: 1e-9)
    }

    // MARK: - Richer weekly-signal reconstruction (additive, backward-compatible with the strain-only path)

    func testRobustRestingHRDropsFeverishOutlierNight() {
        // A single feverish night (skin temp +1.2°C, well past the 0.8°C illness threshold) reads RHR 95 —
        // dropping it should leave the median of the 4 genuinely resting nights, not get pulled toward 95.
        let rhr: [Double] = [58, 60, 59, 95, 61]
        let skin: [Double?] = [0.1, -0.1, 0.2, 1.2, 0.0]
        XCTAssertEqual(FitnessAgeEngine.robustRestingHR(dailyRHR: rhr, skinTempDevC: skin), 59.5, accuracy: 1e-9)
    }

    func testRobustRestingHRFallsBackWhenEveryNightLooksFeverish() {
        // Degenerate case: never return an empty/zero result over real data just because every reading
        // that week happened to cross the threshold — fall back to the plain median instead.
        let rhr: [Double] = [70, 72, 74]
        let skin: [Double?] = [1.0, 1.5, 2.0]
        XCTAssertEqual(FitnessAgeEngine.robustRestingHR(dailyRHR: rhr, skinTempDevC: skin), 72, accuracy: 1e-9)
    }

    func testRobustRestingHRWithNoTempDataMatchesPlainMedian() {
        let rhr: [Double] = [55, 65, 60]
        XCTAssertEqual(FitnessAgeEngine.robustRestingHR(dailyRHR: rhr, skinTempDevC: [nil, nil, nil]), 60, accuracy: 1e-9)
    }

    func testPAIndexFromDailySignalsMatchesStrainOnlyWithoutStepsOrSessions() {
        // No steps/exercise data supplied → identical to the strain-only reconstruction (strict refinement).
        let strainOnly = FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: 4, meanActiveStrain: 60)
        let richer = FitnessAgeEngine.physicalActivityIndexFromDailySignals(activeDaysPerWeek: 4, meanActiveStrain: 60)
        XCTAssertEqual(richer, strainOnly, accuracy: 1e-9)
    }

    func testPAIndexFromDailySignalsStepsCanRaiseDuration() {
        // Low strain (id 1.0) but 10k steps/day (steps id 3.0) blends to 0.7·1.0 + 0.3·3.0 = 1.6,
        // vs. strain-only's 1.0 — a long low-HR walking week should read as MORE active, not the same.
        let strainOnly = FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: 4, meanActiveStrain: 30)
        let richer = FitnessAgeEngine.physicalActivityIndexFromDailySignals(
            activeDaysPerWeek: 4, meanActiveStrain: 30, meanDailySteps: 10000)
        XCTAssertGreaterThan(richer, strainOnly)
        XCTAssertEqual(richer, 2.5 * 1.6, accuracy: 1e-9)
    }

    func testPAIndexFromDailySignalsSessionCountCanRaiseFrequency() {
        // Only 1 day crossed the strain≥30 threshold, but 3 logged exercise sessions that week (e.g. easy
        // yoga/walks that never spiked cardiovascular strain) → frequency should reflect the higher count.
        let richer = FitnessAgeEngine.physicalActivityIndexFromDailySignals(
            activeDaysPerWeek: 1, meanActiveStrain: 20, exerciseSessionsPerWeek: 3)
        // frequency(3) = 2.5, intensityDuration = strain 20/30 = 0.667 (no steps supplied)
        XCTAssertEqual(richer, 2.5 * (20.0 / 30.0), accuracy: 1e-9)
    }

    // MARK: - compute (full result + gates)

    func testComputeReferencePersonExactAge() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 65, paIndex: 5)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fitnessAge, 40.0, accuracy: 1e-9)
        XCTAssertEqual(r!.deltaYears, 0.0, accuracy: 1e-9)
        XCTAssertNil(r!.vo2max)               // no waist → no VO₂max display
        XCTAssertEqual(r!.bandYears, 5.0, accuracy: 1e-9)
        XCTAssertFalse(r!.lowerConfidence)
    }

    func testComputeWithWaistFillsVO2max() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 65, paIndex: 5, waistCm: 90)
        XCTAssertEqual(r!.vo2max!, 46.275, accuracy: 1e-3)
    }

    func testComputeNonBinaryFlagsLowerConfidence() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "nonbinary", restingHR: 60, paIndex: 6)
        XCTAssertTrue(r!.lowerConfidence)
    }

    func testComputeNilWhenNoRHR() {
        XCTAssertNil(FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 0, paIndex: 7.5))
    }

    // MARK: - Readiness checklist

    func testReadinessAllPresentIsReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 7, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .ready)
        XCTAssertTrue(r.canCompute)
        XCTAssertTrue(r.items.allSatisfy { $0.status == .satisfied })
        XCTAssertEqual(r.items.count, 6)
    }

    func testReadinessMissingRHRIsNotReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 0, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .notReady)
        XCTAssertFalse(r.canCompute)
        XCTAssertEqual(r.items.first { $0.key == "rhr" }!.status, .missing)
    }

    func testReadinessPartialCoverageIsEstimate() {
        // age+sex set, 5 nights RHR (≥ min 4 but < good 6), sparse activity → computes, but "estimate".
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 5, activityDays: 3,
                                                 hasHeightWeight: false, hasWaist: false)
        XCTAssertEqual(r.confidence, .estimate)
        XCTAssertTrue(r.canCompute)
        XCTAssertEqual(r.items.first { $0.key == "rhr" }!.status, .partial)
        XCTAssertEqual(r.items.first { $0.key == "activity" }!.status, .partial)
        // Missing body metrics never blocks the headline — they sit under the VO₂max role.
        let body = r.items.first { $0.key == "bodyMetrics" }!
        XCTAssertEqual(body.status, .missing)
        XCTAssertEqual(body.role, .unlocksVO2max)
        XCTAssertFalse(body.required)
    }

    func testReadinessMissingAgeIsNotReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: false, hasSex: true, rhrDays: 7, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .notReady)
    }

    func testReadinessGoodCoverageNoBodyMetricsStillReady() {
        // Headline only needs age/sex/coverage; missing height/weight (VO₂max-only) doesn't drop it.
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 7, activityDays: 6,
                                                 hasHeightWeight: false, hasWaist: false)
        XCTAssertEqual(r.confidence, .ready)
    }
}
