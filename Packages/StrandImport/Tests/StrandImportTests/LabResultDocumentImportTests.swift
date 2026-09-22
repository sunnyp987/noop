import XCTest
@testable import StrandImport

final class LabResultDocumentImportTests: XCTestCase {

    // MARK: - Reference-range interpretation prose must NOT count as "unrecognised"
    //
    // These are the exact lines from a real Quest cholesterol/glucose footnote that kept
    // showing up in the "Not recognised" review list even after the acf118c ALL-CAPS-name
    // filter. Reproducing them here as an actual `swift test` run (not just static reading
    // of looksLikeResultRow) so the failure, if any, is verified rather than assumed.

    func testLipidFootnoteProseIsNotCountedAsUnrecognised() {
        let text = """
        Desirable range <100 mg/dL for primary prevention;
        with > or = 2 CHD risk factors.
        For patients with diabetes plus 1 major ASCVD risk
        factor, treating to a non-HDL-C goal of <100 mg/dL
        Optimal <1.0
        Consider retesting in 1 to 2 weeks to
        Optimal <90
        High > or = 130
        A desirable treatment target may be <80 mg/dL or lower
        diabetes with >1 risk factors, Stage 3 or greater CKD with
        guidelines, hemoglobin A1c <7.0% represents optimal
        made in August 2025 by the reagent manufacturer.
        """
        let result = LabResultDocumentImport.parse(text: text)
        XCTAssertEqual(result.unrecognizedLineCount, 0,
                        "footnote prose leaked through as unrecognised: \(result.unrecognizedSamples)")
        XCTAssertTrue(result.unrecognizedSamples.isEmpty)
    }

    func testOptimalReferenceLineAloneIsNotCountedAsUnrecognised() {
        let result = LabResultDocumentImport.parse(text: "Optimal <1.0")
        XCTAssertEqual(result.unrecognizedLineCount, 0, "\(result.unrecognizedSamples)")
    }

    // MARK: - Genuine ALL-CAPS unknown test names must still count (the filter's actual job)

    func testGenuineUnknownAllCapsTestNameStillCountsAsUnrecognised() {
        let result = LabResultDocumentImport.parse(text: "SOME BRAND NEW MARKER 42 mg/dL")
        XCTAssertEqual(result.unrecognizedLineCount, 1)
        XCTAssertEqual(result.unrecognizedSamples, ["SOME BRAND NEW MARKER 42 mg/dL"])
    }
}
