import Foundation

// MARK: - Calculated lab ratios (an intentional, documented exception)
//
// StrandImport's MarkerCatalog is deliberately non-clinical: no reference ranges, no
// "high/low means X" language, no value judgements (see that file's header). This file
// is a DELIBERATE, EXPLICIT exception to that rule for a small, separate feature: a
// "Calculated" section of well-established ratios (Bilirubin/Albumin, Free Androgen
// Index, AST/ALT, Triglyceride/HDL, and the three CBC-derived inflammation ratios)
// computed on-device from readings the user already saved, with real explanatory text
// (what it measures, why it's checked, what a high/low reading commonly means).
//
// This is a considered product decision, not scope creep into the rest of the app:
// - It only ever touches the 7 ratios defined here — every other marker in the catalog
//   keeps the existing neutral, no-judgement framing untouched.
// - Nothing is asserted as a diagnosis. Explanation text says what clinicians commonly
//   check a marker for, not "you have condition X" — the same register as a patient
//   handout, not a diagnostic tool.
// - A ratio is only computed when its inputs are present AND their printed units can be
//   confidently converted to the units the formula needs. An unrecognised unit means the
//   ratio is silently skipped, never guessed (same "never guess" contract as the rest of
//   the document-scan importer).
public enum DerivedLabRatios {

    /// One raw reading as already stored (value + unit exactly as printed on the report).
    public struct Input: Sendable, Equatable {
        public let value: Double
        public let unit: String
        public let day: String
        public init(value: Double, unit: String, day: String) {
            self.value = value
            self.unit = unit
            self.day = day
        }
    }

    public struct Result: Sendable, Equatable {
        /// MarkerCatalog key this ratio corresponds to (e.g. "neutrophil_lymphocyte_ratio").
        public let key: String
        public let value: Double
        public let unit: String
        /// The most recent day among the inputs that produced this value.
        public let day: String
        /// Catalog keys of the readings this was computed from, for an on-screen "from X, Y" caption.
        public let inputsUsed: [String]
    }

    public struct Explanation: Sendable, Equatable {
        public let whatItMeasures: String
        public let whyItMatters: String
        public let highMeans: String
        public let lowMeans: String
    }

    // MARK: - Public entry point

    public static func compute(from latest: [String: Input]) -> [Result] {
        var out: [Result] = []
        if let r = bilirubinAlbuminRatio(latest) { out.append(r) }
        if let r = freeAndrogenIndex(latest) { out.append(r) }
        if let r = astAltRatio(latest) { out.append(r) }
        if let r = triglycerideHDLRatio(latest) { out.append(r) }
        if let r = neutrophilLymphocyteRatio(latest) { out.append(r) }
        if let r = monocyteLymphocyteRatio(latest) { out.append(r) }
        if let r = plateletLymphocyteRatio(latest) { out.append(r) }
        return out
    }

    // MARK: - Individual ratios

    private static func bilirubinAlbuminRatio(_ latest: [String: Input]) -> Result? {
        guard let bili = latest["total_bilirubin"], let bMgdl = bilirubin_mgdl(bili.value, unit: bili.unit),
              let alb = latest["albumin"], let aGdl = albumin_gdl(alb.value, unit: alb.unit),
              aGdl > 0 else { return nil }
        return Result(key: "bilirubin_albumin_ratio", value: bMgdl / aGdl, unit: "ratio",
                      day: laterDay(bili.day, alb.day), inputsUsed: ["total_bilirubin", "albumin"])
    }

    private static func freeAndrogenIndex(_ latest: [String: Input]) -> Result? {
        guard let t = latest["testosterone_total"], let tNmol = testosterone_nmolL(t.value, unit: t.unit),
              let shbg = latest["shbg"], let sNmol = nmolL_passthrough(shbg.value, unit: shbg.unit),
              sNmol > 0 else { return nil }
        return Result(key: "free_androgen_index", value: (tNmol / sNmol) * 100, unit: "%",
                      day: laterDay(t.day, shbg.day), inputsUsed: ["testosterone_total", "shbg"])
    }

    private static func astAltRatio(_ latest: [String: Input]) -> Result? {
        guard let ast = latest["ast"], let alt = latest["alt"],
              sameEnzymeUnit(ast.unit, alt.unit), alt.value > 0 else { return nil }
        return Result(key: "ast_alt_ratio", value: ast.value / alt.value, unit: "ratio",
                      day: laterDay(ast.day, alt.day), inputsUsed: ["ast", "alt"])
    }

    private static func triglycerideHDLRatio(_ latest: [String: Input]) -> Result? {
        guard let tg = latest["triglycerides"], let tgMgdl = triglycerides_mgdl(tg.value, unit: tg.unit),
              let hdl = latest["hdl"], let hdlMgdl = cholesterol_mgdl(hdl.value, unit: hdl.unit),
              hdlMgdl > 0 else { return nil }
        return Result(key: "triglyceride_hdl_ratio", value: tgMgdl / hdlMgdl, unit: "ratio",
                      day: laterDay(tg.day, hdl.day), inputsUsed: ["triglycerides", "hdl"])
    }

    private static func neutrophilLymphocyteRatio(_ latest: [String: Input]) -> Result? {
        guard let n = latest["neutrophil_absolute"], let nCount = cellCount_perUL(n.value, unit: n.unit),
              let l = latest["lymphocyte_absolute"], let lCount = cellCount_perUL(l.value, unit: l.unit),
              lCount > 0 else { return nil }
        return Result(key: "neutrophil_lymphocyte_ratio", value: nCount / lCount, unit: "ratio",
                      day: laterDay(n.day, l.day), inputsUsed: ["neutrophil_absolute", "lymphocyte_absolute"])
    }

    private static func monocyteLymphocyteRatio(_ latest: [String: Input]) -> Result? {
        guard let m = latest["monocyte_absolute"], let mCount = cellCount_perUL(m.value, unit: m.unit),
              let l = latest["lymphocyte_absolute"], let lCount = cellCount_perUL(l.value, unit: l.unit),
              lCount > 0 else { return nil }
        return Result(key: "monocyte_lymphocyte_ratio", value: mCount / lCount, unit: "ratio",
                      day: laterDay(m.day, l.day), inputsUsed: ["monocyte_absolute", "lymphocyte_absolute"])
    }

    private static func plateletLymphocyteRatio(_ latest: [String: Input]) -> Result? {
        guard let p = latest["platelet_count"], let pCount = cellCount_perUL(p.value, unit: p.unit),
              let l = latest["lymphocyte_absolute"], let lCount = cellCount_perUL(l.value, unit: l.unit),
              lCount > 0 else { return nil }
        return Result(key: "platelet_lymphocyte_ratio", value: pCount / lCount, unit: "ratio",
                      day: laterDay(p.day, l.day), inputsUsed: ["platelet_count", "lymphocyte_absolute"])
    }

    // MARK: - Unit conversions
    //
    // Every converter returns nil (never a guessed number) for a unit it doesn't
    // recognise — the ratio it feeds is then silently skipped, same contract as the
    // rest of the document-scan importer.

    private static func normalizedUnit(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private static func bilirubin_mgdl(_ value: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "mg/dl": return value
        case "µmol/l", "umol/l": return value / 17.1
        default: return nil
        }
    }

    private static func albumin_gdl(_ value: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "g/dl": return value
        case "g/l": return value / 10
        default: return nil
        }
    }

    private static func testosterone_nmolL(_ value: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "nmol/l": return value
        case "ng/dl": return value * 0.0347
        case "ng/ml": return value * 3.467
        default: return nil
        }
    }

    private static func nmolL_passthrough(_ value: Double, unit: String) -> Double? {
        normalizedUnit(unit) == "nmol/l" ? value : nil
    }

    private static func sameEnzymeUnit(_ a: String, _ b: String) -> Bool {
        // AST/ALT are essentially always reported in U/L on the same panel; require an
        // exact (normalised) match rather than assume, since a mismatch would silently
        // scale one side wrong.
        normalizedUnit(a) == normalizedUnit(b) && normalizedUnit(a) == "u/l"
    }

    private static func triglycerides_mgdl(_ value: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "mg/dl": return value
        case "mmol/l": return value * 88.57
        default: return nil
        }
    }

    private static func cholesterol_mgdl(_ value: Double, unit: String) -> Double? {
        switch normalizedUnit(unit) {
        case "mg/dl": return value
        case "mmol/l": return value * 38.67
        default: return nil
        }
    }

    /// Absolute cell counts print at wildly different scales across labs — a raw
    /// "cells/uL"/"/mm3" count (thousands, e.g. 2232) vs a scaled "Thousand/uL",
    /// "10^9/L" or "K/uL" reading (single digits, e.g. 2.23) that represents the SAME
    /// real count. Normalises everything to raw cells/µL so a ratio never silently
    /// comes out 1000x wrong from mixing scales.
    private static func cellCount_perUL(_ value: Double, unit: String) -> Double? {
        let u = normalizedUnit(unit)
        let scaledUnits: Set<String> = [
            "thousand/ul", "thousand/µl", "10^9/l", "10e9/l", "x10^9/l", "10^3/ul",
            "10^3/µl", "k/ul", "k/µl", "thousand/mm3",
        ]
        let rawUnits: Set<String> = ["cells/ul", "cells/µl", "/ul", "/µl", "cells/mm3", "/mm3"]
        if scaledUnits.contains(u) { return value * 1000 }
        if rawUnits.contains(u) { return value }
        return nil
    }

    private static func laterDay(_ a: String, _ b: String) -> String { max(a, b) }

    // MARK: - Explanations (plain-language, patient-handout register — not a diagnosis)

    public static let explanations: [String: Explanation] = [
        "bilirubin_albumin_ratio": Explanation(
            whatItMeasures: "Total bilirubin (a byproduct of red blood cell breakdown, cleared by the liver) divided by albumin (a protein the liver makes).",
            whyItMatters: "Combining the two into one ratio is used as a quick liver-function screen — it moves when either the liver's clearance of bilirubin or its protein production changes, even before either number alone looks unusual.",
            highMeans: "A higher ratio is usually driven by rising bilirubin, low albumin, or both — patterns doctors associate with reduced liver function or, in newborns, a marker tracked for jaundice risk. It's a screening signal, not a diagnosis; a doctor would follow up with the individual liver panel values and, if needed, further testing.",
            lowMeans: "A lower ratio isn't a recognised clinical concern on its own — it simply reflects low bilirubin and/or higher albumin, both generally unremarkable findings."
        ),
        "free_androgen_index": Explanation(
            whatItMeasures: "Total testosterone divided by SHBG (sex hormone-binding globulin, the protein that binds most testosterone in the blood and makes it inactive), scaled to a percentage.",
            whyItMatters: "Only testosterone that isn't bound to SHBG is biologically active. Two people can have identical total testosterone but very different amounts of it actually available to tissues, depending on their SHBG — this index estimates that available fraction.",
            highMeans: "A high FAI suggests a larger share of testosterone is free/active relative to how much is bound. In women, a persistently high FAI is one of the patterns doctors check for alongside symptoms like irregular cycles or acne (e.g. as part of a PCOS work-up). In men, it's generally just read alongside total testosterone rather than flagged on its own.",
            lowMeans: "A low FAI usually means SHBG is relatively high compared to total testosterone — common with high SHBG states (e.g. hyperthyroidism, some liver conditions, oestrogen therapy) — meaning less of the testosterone present is actually active, even if the total number looks normal."
        ),
        "ast_alt_ratio": Explanation(
            whatItMeasures: "AST divided by ALT — two liver enzymes that both rise when liver cells are damaged, but not always by the same amount or for the same reason.",
            whyItMatters: "Known clinically as the De Ritis ratio. Because AST and ALT come from slightly different sources in the liver (and AST also from muscle/heart), the RATIO between them — not just whether either is elevated — helps suggest what pattern of liver stress is happening.",
            highMeans: "A ratio clearly above 1 (AST notably higher than ALT) is a pattern more often seen with alcohol-related liver stress or more advanced liver scarring (cirrhosis), where AST tends to stay elevated longer than ALT.",
            lowMeans: "A ratio below 1 (ALT higher than AST) is the more common pattern in early/mild liver stress not related to alcohol — for example fatty liver — where ALT typically rises faster than AST."
        ),
        "triglyceride_hdl_ratio": Explanation(
            whatItMeasures: "Triglycerides divided by HDL cholesterol (\"good\" cholesterol).",
            whyItMatters: "This ratio is widely used as a rough, low-cost proxy for insulin resistance and for how many small, dense LDL particles (the more artery-damaging kind) are likely present — information the standard cholesterol panel doesn't directly show.",
            highMeans: "A high ratio (commonly cited threshold: above ~3 in mg/dL units) is associated with a pattern of more insulin resistance and a higher proportion of small, dense LDL particles, both linked to higher cardiovascular risk — even when total and LDL cholesterol look otherwise normal.",
            lowMeans: "A low ratio is generally reassuring — it suggests a healthier balance between triglycerides and HDL and is associated with larger, less artery-damaging LDL particles."
        ),
        "neutrophil_lymphocyte_ratio": Explanation(
            whatItMeasures: "Absolute neutrophils divided by absolute lymphocytes — two types of white blood cells with opposite jobs: neutrophils lead the acute/inflammatory response, lymphocytes lead the adaptive immune response.",
            whyItMatters: "Known as NLR. It's a simple, inexpensive marker of systemic inflammation and physiological stress, increasingly used alongside other findings to gauge how much inflammatory load the body is currently under.",
            highMeans: "A high NLR reflects a shift toward the inflammatory/stress response — seen with acute infection, injury, significant physical or psychological stress, and is also studied as a general marker of inflammation-related health risk when persistently elevated.",
            lowMeans: "A low NLR generally reflects a calmer inflammatory state, though a very low ratio can also reflect a lower neutrophil count on its own — worth reading alongside the individual white cell counts rather than in isolation."
        ),
        "monocyte_lymphocyte_ratio": Explanation(
            whatItMeasures: "Absolute monocytes divided by absolute lymphocytes — monocytes are another inflammatory-response white cell (precursors to macrophages), lymphocytes lead the adaptive immune response.",
            whyItMatters: "Known as MLR. Like NLR, it's used as a low-cost general inflammation signal, and is separately studied in the context of chronic/long-term inflammatory load rather than acute stress specifically.",
            highMeans: "A high MLR suggests relatively more monocyte-driven inflammatory activity compared to lymphocyte activity — a pattern studied alongside chronic inflammatory and cardiovascular risk markers.",
            lowMeans: "A low MLR generally reflects a calmer inflammatory state relative to lymphocyte activity."
        ),
        "platelet_lymphocyte_ratio": Explanation(
            whatItMeasures: "Platelet count divided by absolute lymphocytes — platelets are involved in clotting and also participate in inflammation; lymphocytes lead the adaptive immune response.",
            whyItMatters: "Known as PLR. It's another simple combined marker of inflammation and clotting-related activity, often looked at together with NLR rather than alone.",
            highMeans: "A high PLR reflects relatively more platelet activity compared to lymphocyte activity — a pattern associated with higher inflammatory and clotting-related activity in research contexts.",
            lowMeans: "A low PLR generally reflects a calmer inflammatory/clotting-related state relative to lymphocyte activity."
        ),
    ]
}
