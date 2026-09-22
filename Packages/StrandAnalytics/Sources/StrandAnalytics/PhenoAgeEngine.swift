import Foundation

// PhenoAgeEngine.swift — the published clinical-chemistry biological-age formula from
// Levine ME et al., "An epigenetic biomarker of aging for lifespan and healthspan",
// Aging (Albany NY) 2018;10(4):573-591. This is the "phenotypic age" half of that paper
// (built from ordinary blood-panel biomarkers, no DNA methylation array involved) —
// widely reproduced since in follow-up biological-age research and open-source
// calculators, using the same nine inputs plus chronological age.
//
// UNLIKE BiometricAgeEngine (Baseline's own in-house composite, which degrades gracefully
// with partial data and caps each domain individually before combining), this is someone
// ELSE's fully-specified formula: a single linear combination inside a Gompertz mortality
// model. Feeding it partial inputs wouldn't reproduce the paper's model at all, so
// `compute` requires all nine markers and returns nil otherwise — an honest "add the rest
// of your panel" rather than a look-alike number computed a different way.
//
// A full panel (CBC + a metabolic panel + hs-CRP) covers every one of these nine markers,
// which is exactly what a comprehensive consumer panel (Superpower, Function Health, or a
// doctor-ordered CBC/CMP + CRP) already reports — so this is usable the moment such a
// panel lands in the Lab Book, with no extra draw beyond what many people already get.
public enum PhenoAgeEngine {

    /// One lab value paired with the exact unit string it was stored under (Lab Book never
    /// converts units on entry — see LabMarkerCsvImport's header — so PhenoAgeEngine has to
    /// interpret whatever unit actually came in). `nil` unit is treated as already being in
    /// the formula's expected unit (the common case for markers with no real US/SI split).
    public struct Reading: Sendable {
        public let value: Double
        public let unit: String?
        public init(value: Double, unit: String?) { self.value = value; self.unit = unit }
    }

    public struct Inputs: Sendable {
        public let chronoAge: Double
        public let albumin: Reading           // formula wants g/L
        public let creatinine: Reading        // formula wants µmol/L
        public let glucose: Reading           // formula wants mmol/L
        public let crp: Reading               // formula wants mg/L (log-transformed)
        public let lymphocytePct: Reading     // %
        public let mcv: Reading               // fL
        public let rdw: Reading               // %
        public let alkalinePhosphatase: Reading // U/L
        public let wbc: Reading               // formula wants 10^9/L (= K/µL)

        public init(chronoAge: Double, albumin: Reading, creatinine: Reading, glucose: Reading,
                    crp: Reading, lymphocytePct: Reading, mcv: Reading, rdw: Reading,
                    alkalinePhosphatase: Reading, wbc: Reading) {
            self.chronoAge = chronoAge; self.albumin = albumin; self.creatinine = creatinine
            self.glucose = glucose; self.crp = crp; self.lymphocytePct = lymphocytePct
            self.mcv = mcv; self.rdw = rdw; self.alkalinePhosphatase = alkalinePhosphatase; self.wbc = wbc
        }
    }

    public struct Result: Equatable, Sendable {
        /// "Phenotypic Age" in years, straight from the published formula.
        public let phenoAge: Double
        /// phenoAge - chronoAge; positive means the panel reads OLDER than your actual age.
        public let deltaYears: Double
    }

    // MARK: - Published coefficients (Levine et al. 2018, Table/Methods)

    private static let b0 = -19.907
    private static let bAlbumin = -0.0336            // per g/L
    private static let bCreatinine = 0.0095          // per µmol/L
    private static let bGlucose = 0.1953              // per mmol/L
    private static let bLnCRP = 0.0954                // per ln(mg/L)
    private static let bLymphocyte = -0.0120          // per %
    private static let bMCV = 0.0268                  // per fL
    private static let bRDW = 0.3306                  // per %
    private static let bALP = 0.00188                 // per U/L
    private static let bWBC = 0.0554                  // per 10^9/L
    private static let bAge = 0.0804                  // per year
    private static let gamma = 0.0076927
    private static let const1 = 141.50225
    private static let const2 = 0.0055305             // "-0.00553" in the paper, kept positive here (see below)
    private static let const3 = 0.090165

    /// A CRP of exactly 0 would send `ln(CRP)` to -infinity; every open implementation of
    /// this formula floors CRP at a small positive value first (below the sensitivity of
    /// any real assay anyway), so a genuinely undetectable CRP doesn't blow up the model.
    private static let crpFloor = 0.01

    public static func compute(_ i: Inputs) -> Result? {
        guard
            let albumin = normalizeAlbumin(i.albumin),
            let creatinine = normalizeCreatinine(i.creatinine),
            let glucose = normalizeGlucose(i.glucose),
            let crp = normalizeCRP(i.crp),
            let lymph = plain(i.lymphocytePct),
            let mcv = plain(i.mcv),
            let rdw = plain(i.rdw),
            let alp = plain(i.alkalinePhosphatase),
            let wbc = normalizeWBC(i.wbc)
        else { return nil }

        let crpForLn = max(crp, crpFloor)
        let xb = b0
            + bAlbumin * albumin
            + bCreatinine * creatinine
            + bGlucose * glucose
            + bLnCRP * log(crpForLn)
            + bLymphocyte * lymph
            + bMCV * mcv
            + bRDW * rdw
            + bALP * alp
            + bWBC * wbc
            + bAge * i.chronoAge

        // Gompertz mortality-score transform back to years (Levine et al., Methods).
        let mortalityScore = 1 - exp(-exp(xb) * (exp(120 * gamma) - 1) / gamma)
        guard mortalityScore > 0, mortalityScore < 1 else { return nil }   // outside the model's valid range
        let phenoAge = const1 + log(-const2 * log(1 - mortalityScore)) / const3
        guard phenoAge.isFinite else { return nil }

        return Result(phenoAge: phenoAge, deltaYears: phenoAge - i.chronoAge)
    }

    // MARK: - Unit normalization (best-effort; the ambiguous US/SI markers only)

    /// No real US/SI split for these (%, fL, U/L read the same everywhere in practice).
    private static func plain(_ r: Reading) -> Double? { r.value.isFinite ? r.value : nil }

    /// g/dL (US convention, typically 3-5) vs g/L (SI, typically 30-50). A value under 20 is
    /// almost certainly g/dL even with no unit string (SI albumin is never that low).
    private static func normalizeAlbumin(_ r: Reading) -> Double? {
        guard r.value.isFinite else { return nil }
        let u = (r.unit ?? "").lowercased()
        if u.contains("dl") || (u.isEmpty && r.value < 20) { return r.value * 10 }
        return r.value
    }

    /// mg/dL (US, typically 0.5-1.5) vs µmol/L (SI, typically 45-135). A bare value under 20
    /// reads as mg/dL — µmol/L creatinine is never that low for a real reading.
    private static func normalizeCreatinine(_ r: Reading) -> Double? {
        guard r.value.isFinite else { return nil }
        let u = (r.unit ?? "").lowercased()
        if u.contains("dl") || (u.isEmpty && r.value < 20) { return r.value * 88.4 }
        return r.value
    }

    /// mg/dL (US, typically 70-140) vs mmol/L (SI, typically 4-8). A bare value over 20 reads
    /// as mg/dL — SI fasting glucose is never that high.
    private static func normalizeGlucose(_ r: Reading) -> Double? {
        guard r.value.isFinite else { return nil }
        let u = (r.unit ?? "").lowercased()
        if u.contains("mg") || (u.isEmpty && r.value > 20) { return r.value * 0.0555 }
        return r.value
    }

    /// mg/dL vs the formula's mg/L — CRP is almost always already reported in mg/L on a
    /// modern hs-CRP panel, so only convert when the unit explicitly says dL.
    private static func normalizeCRP(_ r: Reading) -> Double? {
        guard r.value.isFinite, r.value >= 0 else { return nil }
        let u = (r.unit ?? "").lowercased()
        if u.contains("dl") { return r.value * 10 }
        return r.value
    }

    /// Raw cells/µL (e.g. "6200") vs 10^9/L = K/µL (e.g. "6.2"). A real WBC count in 10^9/L is
    /// essentially always under 50; a raw cells/µL count is essentially always over 500.
    private static func normalizeWBC(_ r: Reading) -> Double? {
        guard r.value.isFinite, r.value >= 0 else { return nil }
        if r.value > 500 { return r.value / 1000 }
        return r.value
    }

    // MARK: - Diagnosis (why `compute` returned nil, precisely — not a guess)

    /// One input, after the SAME unit-normalization `compute` applies, checked against a broad
    /// PHYSIOLOGICAL-PLAUSIBILITY envelope (not a clinical/optimal range — just "a living person
    /// cannot have this value"). Flags a value at least 3× outside that envelope, which is the
    /// signature of a scan error (a dropped decimal point, a doubled digit, a swapped unit) rather
    /// than a genuinely extreme-but-real result.
    public struct Flag: Sendable, Equatable {
        /// The MarkerCatalog key ("crp", "mcv", …) — NOT a display string, so the caller can look
        /// the display name up from a single source of truth (MarkerCatalog) instead of two files
        /// having to agree on hand-typed label text that can silently drift apart.
        public let key: String
        public let normalizedValue: Double
        public let unit: String
        /// The broad plausibility envelope this value fell outside of.
        public let plausibleRange: ClosedRange<Double>
    }

    /// Runs every input through the same normalization `compute` uses and flags any that lands
    /// outside a generous physiological envelope — wide enough to include real extreme results,
    /// narrow enough to catch a scan misread. Returns every implausible marker, in the fixed
    /// formula order, so the caller can name the exact one(s) to check rather than listing all nine.
    /// Keys match the ones `HealthView.PhenoAgeSection.requiredKeys` reads from the Lab Book.
    public static func diagnose(_ i: Inputs) -> [Flag] {
        var flags: [Flag] = []
        func check(_ key: String, _ v: Double?, unit: String, _ range: ClosedRange<Double>) {
            guard let v, v.isFinite else { return }
            if !range.contains(v) {
                flags.append(Flag(key: key, normalizedValue: v, unit: unit, plausibleRange: range))
            }
        }
        check("albumin", normalizeAlbumin(i.albumin), unit: "g/L", 10...70)
        check("creatinine", normalizeCreatinine(i.creatinine), unit: "µmol/L", 15...2000)
        check("fasting_glucose", normalizeGlucose(i.glucose), unit: "mmol/L", 1...45)
        check("crp", normalizeCRP(i.crp), unit: "mg/L", 0...500)
        check("lymphocyte_pct", plain(i.lymphocytePct), unit: "%", 0...100)
        check("mcv", plain(i.mcv), unit: "fL", 40...150)
        check("rdw", plain(i.rdw), unit: "%", 8...30)
        check("alkaline_phosphatase", plain(i.alkalinePhosphatase), unit: "U/L", 5...2000)
        check("wbc_count", normalizeWBC(i.wbc), unit: "10^9/L", 0.3...100)
        return flags
    }
}
