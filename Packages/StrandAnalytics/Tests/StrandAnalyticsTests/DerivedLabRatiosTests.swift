import XCTest
@testable import StrandAnalytics

final class DerivedLabRatiosTests: XCTestCase {

    private func input(_ value: Double, _ unit: String, day: String = "2026-01-01") -> DerivedLabRatios.Input {
        DerivedLabRatios.Input(value: value, unit: unit, day: day)
    }

    func testBilirubinAlbuminRatioConvertsUnits() {
        // 17.1 umol/L bilirubin (~1.0 mg/dL) over 40 g/L albumin (4.0 g/dL) -> ~0.25
        let latest = [
            "total_bilirubin": input(17.1, "µmol/L"),
            "albumin": input(40, "g/L"),
        ]
        let results = DerivedLabRatios.compute(from: latest)
        guard let r = results.first(where: { $0.key == "bilirubin_albumin_ratio" }) else {
            return XCTFail("expected bilirubin_albumin_ratio")
        }
        XCTAssertEqual(r.value, 0.25, accuracy: 0.01)
    }

    func testFreeAndrogenIndexPercentage() {
        let latest = [
            "testosterone_total": input(1.0, "nmol/L"),
            "shbg": input(50, "nmol/L"),
        ]
        let results = DerivedLabRatios.compute(from: latest)
        guard let r = results.first(where: { $0.key == "free_androgen_index" }) else {
            return XCTFail("expected free_androgen_index")
        }
        XCTAssertEqual(r.value, 2.0, accuracy: 0.001)
    }

    func testAstAltRatioRequiresMatchingUnits() {
        let mismatched = [
            "ast": input(30, "U/L"),
            "alt": input(20, "IU/L"),
        ]
        XCTAssertNil(DerivedLabRatios.compute(from: mismatched).first(where: { $0.key == "ast_alt_ratio" }))

        let matched = [
            "ast": input(30, "U/L"),
            "alt": input(20, "U/L"),
        ]
        let r = DerivedLabRatios.compute(from: matched).first(where: { $0.key == "ast_alt_ratio" })
        XCTAssertEqual(r?.value, 1.5, accuracy: 0.001)
    }

    func testPlateletLymphocyteRatioNormalizesScaledCellCounts() {
        // Platelets printed as "Thousand/uL" (187), lymphocytes as raw "cells/uL" (1982).
        let latest = [
            "platelet_count": input(187, "Thousand/uL"),
            "lymphocyte_absolute": input(1982, "cells/uL"),
        ]
        let r = DerivedLabRatios.compute(from: latest).first(where: { $0.key == "platelet_lymphocyte_ratio" })
        // 187_000 / 1982 ≈ 94.35 — proves the 1000x scale mismatch was corrected, not left raw (187/1982).
        XCTAssertEqual(r?.value ?? 0, 94.35, accuracy: 0.5)
    }

    func testUnrecognizedUnitSkipsRatherThanGuesses() {
        let latest = [
            "platelet_count": input(187, "mystery-unit"),
            "lymphocyte_absolute": input(1982, "cells/uL"),
        ]
        XCTAssertNil(DerivedLabRatios.compute(from: latest).first(where: { $0.key == "platelet_lymphocyte_ratio" }))
    }

    func testMissingInputSkipsRatio() {
        let latest = ["ast": input(30, "U/L")]
        XCTAssertTrue(DerivedLabRatios.compute(from: latest).isEmpty)
    }

    func testEveryComputableRatioHasAnExplanation() {
        for key in ["bilirubin_albumin_ratio", "free_androgen_index", "ast_alt_ratio",
                    "triglyceride_hdl_ratio", "neutrophil_lymphocyte_ratio",
                    "monocyte_lymphocyte_ratio", "platelet_lymphocyte_ratio"] {
            XCTAssertNotNil(DerivedLabRatios.explanations[key], "missing explanation for \(key)")
        }
    }
}
