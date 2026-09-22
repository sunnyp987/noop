import Foundation

// MARK: - Marker dictionary (non-diagnostic)
//
// MarkerCatalog.swift — a small dictionary of common, NON-DIAGNOSTIC marker
// definitions so the user can pick a marker by name (with a sensible canonical unit
// and decimal precision prefilled) instead of typing everything free-hand.
//
// Per the Health Records design spec (2026-06-19-v5-health-records-design.md,
// §"New" and §"Non-clinical / legal framing"):
//   - This ships NO reference-range tables. `referenceTextHint` is a neutral
//     placeholder prompting the user to copy the range FROM THEIR OWN REPORT — NOOP
//     never defines, computes, or asserts a normal range.
//   - `higherIsBetter` is intentionally `nil` for every entry: NOOP makes no value
//     judgement about a marker's direction. The field exists only so a future
//     descriptive sparkline could phrase a trend, never a clinical verdict.
//   - The catalog is NOT a gate: a user can always add a custom marker (free name +
//     unit), so the store is never limited by this dictionary.
//
// Pure data — no DB, no I/O. Mirrors the flat, deterministic style of the other
// StrandImport model files.

/// A non-diagnostic marker definition: how to label and format one marker the user
/// chooses from the picker. Carries NO clinical thresholds.
public struct MarkerDefinition: Sendable, Equatable, Codable {
    /// Stable key stored on every `LabMarker` (e.g. `"ldl"`, `"bp_systolic"`).
    public let key: String
    /// Human display name (e.g. `"LDL cholesterol"`).
    public let displayName: String
    /// Organisational category for grouping in the Lab Book.
    public let category: LabMarkerCategory
    /// Canonical unit prefilled in the editor (e.g. `"mmol/L"`, `"mmHg"`).
    public let canonicalUnit: String
    /// How many decimal places to show for this marker's values.
    public let decimals: Int
    /// Neutral placeholder prompting the user to copy the range from their own
    /// report. NOT a shipped reference range (see file header). `nil` where a range
    /// makes no sense (e.g. body measurements, notes).
    public let referenceTextHint: String?
    /// Direction hint — ALWAYS `nil` (NOOP makes no value judgement). Present only as
    /// a deliberate, documented placeholder so no caller infers a default of `true`.
    public let higherIsBetter: Bool?

    public init(
        key: String,
        displayName: String,
        category: LabMarkerCategory,
        canonicalUnit: String,
        decimals: Int,
        referenceTextHint: String? = nil,
        higherIsBetter: Bool? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.category = category
        self.canonicalUnit = canonicalUnit
        self.decimals = decimals
        self.referenceTextHint = referenceTextHint
        self.higherIsBetter = higherIsBetter
    }
}

/// The built-in, non-diagnostic marker dictionary. Extensible at runtime via custom
/// markers — see `custom(key:displayName:unit:)`.
public enum MarkerCatalog {

    /// A neutral hint shown in the range field — the user copies their own report's
    /// range here; NOOP ships none.
    private static let fromReport = "From your own report (optional)"

    /// ~30 common markers across the categories. Order is the suggested picker order.
    /// Reference hints are neutral prompts only; `higherIsBetter` is `nil` everywhere.
    public static let builtIn: [MarkerDefinition] = [
        // Lipids (blood panel)
        .init(key: "total_cholesterol", displayName: "Total cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "ldl", displayName: "LDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "hdl", displayName: "HDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "triglycerides", displayName: "Triglycerides", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        // Glucose
        .init(key: "fasting_glucose", displayName: "Fasting glucose", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "hba1c", displayName: "HbA1c", category: .bloodPanel, canonicalUnit: "mmol/mol", decimals: 0, referenceTextHint: fromReport),
        .init(key: "estimated_average_glucose", displayName: "Estimated average glucose (eAG)", category: .bloodPanel, canonicalUnit: "mg/dL", decimals: 0, referenceTextHint: fromReport),
        // Not in every panel (e.g. missing from a first Superpower run) but common enough on a
        // follow-up metabolic panel to be worth a slot of its own rather than falling to a custom marker.
        .init(key: "fasting_insulin", displayName: "Fasting insulin", category: .bloodPanel, canonicalUnit: "µIU/mL", decimals: 1, referenceTextHint: fromReport),
        // Iron studies
        .init(key: "ferritin", displayName: "Ferritin", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "iron", displayName: "Serum iron", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "transferrin_saturation", displayName: "Transferrin saturation", category: .bloodPanel, canonicalUnit: "%", decimals: 0, referenceTextHint: fromReport),
        .init(key: "haemoglobin", displayName: "Haemoglobin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        // Vitamins
        .init(key: "vitamin_d", displayName: "Vitamin D", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "vitamin_b12", displayName: "Vitamin B12", category: .bloodPanel, canonicalUnit: "ng/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "folate", displayName: "Folate", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 1, referenceTextHint: fromReport),
        // Thyroid
        .init(key: "tsh", displayName: "TSH", category: .bloodPanel, canonicalUnit: "mIU/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "free_t4", displayName: "Free T4", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 1, referenceTextHint: fromReport),
        // Inflammation
        .init(key: "crp", displayName: "C-reactive protein (CRP)", category: .bloodPanel, canonicalUnit: "mg/L", decimals: 1, referenceTextHint: fromReport),
        // Kidney
        .init(key: "egfr", displayName: "eGFR", category: .bloodPanel, canonicalUnit: "mL/min/1.73m²", decimals: 0, referenceTextHint: fromReport),
        // decimals: 2 (not 0) even though the canonical SI unit (µmol/L) is usually whole —
        // US reports print mg/dL, where the meaningful range is ~0.6-1.3 and rounding to 0
        // decimals collapses every real reading down to "1".
        .init(key: "creatinine", displayName: "Creatinine", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 2, referenceTextHint: fromReport),
        // Liver
        .init(key: "alt", displayName: "ALT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ast", displayName: "AST", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ggt", displayName: "GGT", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        // Electrolytes
        .init(key: "sodium", displayName: "Sodium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "potassium", displayName: "Potassium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        // Protein + CBC panel (added so a full blood-panel export — e.g. Superpower, or any
        // CBC + CMP + hs-CRP panel — can feed StrandAnalytics.PhenoAgeEngine, the published
        // Levine et al. 2018 clinical-chemistry biological-age formula; canonicalUnit here is
        // the unit THAT FORMULA expects, PhenoAgeEngine normalises common alternate units).
        .init(key: "albumin", displayName: "Albumin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "lymphocyte_pct", displayName: "Lymphocyte %", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "mcv", displayName: "MCV (mean cell volume)", category: .bloodPanel, canonicalUnit: "fL", decimals: 1, referenceTextHint: fromReport),
        .init(key: "rdw", displayName: "RDW (red cell distribution width)", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "alkaline_phosphatase", displayName: "Alkaline phosphatase (ALP)", category: .bloodPanel, canonicalUnit: "U/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "wbc_count", displayName: "White blood cell count (WBC)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 1, referenceTextHint: fromReport),
        // Extended lipids (a full panel/Superpower-style report goes well beyond the basic 4).
        .init(key: "non_hdl_cholesterol", displayName: "Non-HDL cholesterol", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "apob", displayName: "Apolipoprotein B (ApoB)", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "apoa1", displayName: "Apolipoprotein A1 (ApoA1)", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "lp_a", displayName: "Lipoprotein(a)", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "cholesterol_hdl_ratio", displayName: "Total cholesterol/HDL ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 1, referenceTextHint: fromReport),
        // Extended metabolic
        .init(key: "homa_ir", displayName: "HOMA-IR (insulin resistance)", category: .bloodPanel, canonicalUnit: "score", decimals: 2, referenceTextHint: fromReport),
        .init(key: "c_peptide", displayName: "C-peptide", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "fructosamine", displayName: "Fructosamine", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 0, referenceTextHint: fromReport),
        // decimals: 1 (not 0) — same reasoning as creatinine: US reports print mg/dL
        // (~3.5-8.0), where a real reading like "4.2" would otherwise round down to "4".
        .init(key: "uric_acid", displayName: "Uric acid", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        // Extended kidney
        .init(key: "bun", displayName: "Blood urea nitrogen (BUN)", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "bun_creatinine_ratio", displayName: "BUN/creatinine ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 1, referenceTextHint: fromReport),
        .init(key: "cystatin_c", displayName: "Cystatin C", category: .bloodPanel, canonicalUnit: "mg/L", decimals: 2, referenceTextHint: fromReport),
        // Extended liver
        .init(key: "total_bilirubin", displayName: "Total bilirubin", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "direct_bilirubin", displayName: "Direct bilirubin", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "indirect_bilirubin", displayName: "Indirect bilirubin", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "total_protein", displayName: "Total protein", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "globulin", displayName: "Globulin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ag_ratio", displayName: "Albumin/globulin ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        // Extended electrolytes + minerals
        .init(key: "calcium", displayName: "Calcium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "magnesium", displayName: "Magnesium", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "phosphorus", displayName: "Phosphorus", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "chloride", displayName: "Chloride", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "co2", displayName: "Carbon dioxide (CO2/bicarbonate)", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "zinc", displayName: "Zinc", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "copper", displayName: "Copper", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "selenium", displayName: "Selenium", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "magnesium_rbc", displayName: "Magnesium, RBC", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        // Extended CBC (differential + red-cell indices) — the rest of a standard CBC beyond
        // what PhenoAgeEngine already needs (albumin/lymphocyte%/MCV/RDW/WBC above).
        .init(key: "rbc_count", displayName: "Red blood cell count (RBC)", category: .bloodPanel, canonicalUnit: "10^12/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "hematocrit", displayName: "Hematocrit", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "platelet_count", displayName: "Platelet count", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "mch", displayName: "MCH (mean cell haemoglobin)", category: .bloodPanel, canonicalUnit: "pg", decimals: 1, referenceTextHint: fromReport),
        .init(key: "mchc", displayName: "MCHC", category: .bloodPanel, canonicalUnit: "g/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "mpv", displayName: "MPV (mean platelet volume)", category: .bloodPanel, canonicalUnit: "fL", decimals: 1, referenceTextHint: fromReport),
        .init(key: "neutrophil_pct", displayName: "Neutrophils %", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "monocyte_pct", displayName: "Monocytes %", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "eosinophil_pct", displayName: "Eosinophils %", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "basophil_pct", displayName: "Basophils %", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        // Extended thyroid
        .init(key: "free_t3", displayName: "Free T3", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "total_t3", displayName: "Total T3", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "total_t4", displayName: "Total T4", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "reverse_t3", displayName: "Reverse T3", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "tpo_antibodies", displayName: "Thyroid peroxidase antibodies (TPO)", category: .bloodPanel, canonicalUnit: "IU/mL", decimals: 0, referenceTextHint: fromReport),
        .init(key: "thyroglobulin_antibodies", displayName: "Thyroglobulin antibodies", category: .bloodPanel, canonicalUnit: "IU/mL", decimals: 0, referenceTextHint: fromReport),
        .init(key: "t3_uptake", displayName: "T3 uptake", category: .bloodPanel, canonicalUnit: "%", decimals: 0, referenceTextHint: fromReport),
        .init(key: "free_t4_index", displayName: "Free T4 index (T7)", category: .bloodPanel, canonicalUnit: "index", decimals: 1, referenceTextHint: fromReport),
        // Hormones
        .init(key: "testosterone_total", displayName: "Testosterone, total", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "testosterone_free", displayName: "Testosterone, free", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "shbg", displayName: "SHBG", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "estradiol", displayName: "Estradiol", category: .bloodPanel, canonicalUnit: "pmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "progesterone", displayName: "Progesterone", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "dhea_s", displayName: "DHEA-S", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "cortisol", displayName: "Cortisol", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "lh", displayName: "LH (luteinizing hormone)", category: .bloodPanel, canonicalUnit: "IU/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "fsh", displayName: "FSH (follicle-stimulating hormone)", category: .bloodPanel, canonicalUnit: "IU/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "prolactin", displayName: "Prolactin", category: .bloodPanel, canonicalUnit: "mIU/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "igf_1", displayName: "IGF-1", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "psa", displayName: "PSA (prostate-specific antigen)", category: .bloodPanel, canonicalUnit: "µg/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "testosterone_bioavailable", displayName: "Testosterone, bioavailable", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 1, referenceTextHint: fromReport),
        // Extended vitamins + inflammation
        .init(key: "vitamin_a", displayName: "Vitamin A", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "vitamin_e", displayName: "Vitamin E", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "vitamin_k", displayName: "Vitamin K", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "homocysteine", displayName: "Homocysteine", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "omega_3_index", displayName: "Omega-3 index", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        .init(key: "esr", displayName: "ESR (sed rate)", category: .bloodPanel, canonicalUnit: "mm/hr", decimals: 0, referenceTextHint: fromReport),
        .init(key: "fibrinogen", displayName: "Fibrinogen", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "tibc", displayName: "TIBC (total iron-binding capacity)", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "transferrin", displayName: "Transferrin", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "rbc_folate", displayName: "RBC folate", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "methylmalonic_acid", displayName: "Methylmalonic acid (MMA)", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "vitamin_b6", displayName: "Vitamin B6", category: .bloodPanel, canonicalUnit: "nmol/L", decimals: 0, referenceTextHint: fromReport),
        .init(key: "corrected_calcium", displayName: "Corrected calcium (albumin-adjusted)", category: .bloodPanel, canonicalUnit: "mmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "oxidized_ldl", displayName: "Oxidized LDL", category: .bloodPanel, canonicalUnit: "U/L", decimals: 1, referenceTextHint: fromReport),
        .init(key: "adma", displayName: "Asymmetric dimethylarginine (ADMA)", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "sdma", displayName: "Symmetric dimethylarginine (SDMA)", category: .bloodPanel, canonicalUnit: "µmol/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "cystatin_c_egfr", displayName: "Cystatin C-based eGFR", category: .bloodPanel, canonicalUnit: "mL/min/1.73m²", decimals: 0, referenceTextHint: fromReport),
        // Absolute CBC differential counts (the percentages above cover the same cells as a ratio).
        .init(key: "neutrophil_absolute", displayName: "Neutrophils (absolute)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "lymphocyte_absolute", displayName: "Lymphocytes (absolute)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "monocyte_absolute", displayName: "Monocytes (absolute)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "eosinophil_absolute", displayName: "Eosinophils (absolute)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "basophil_absolute", displayName: "Basophils (absolute)", category: .bloodPanel, canonicalUnit: "10^9/L", decimals: 2, referenceTextHint: fromReport),
        // Immune / autoimmune panel — reported as a titer/value+unit row on most panels, so these
        // fit the same (name, value, unit) shape as everything else, even though a positive/negative
        // read is ultimately a clinical call Baseline never makes.
        .init(key: "immunoglobulin_a", displayName: "Immunoglobulin A (IgA)", category: .bloodPanel, canonicalUnit: "g/L", decimals: 2, referenceTextHint: fromReport),
        .init(key: "immunoglobulin_e", displayName: "Immunoglobulin E (IgE)", category: .bloodPanel, canonicalUnit: "IU/mL", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ana_titer", displayName: "Antinuclear antibodies (ANA)", category: .bloodPanel, canonicalUnit: "titer", decimals: 0, referenceTextHint: fromReport),
        .init(key: "rheumatoid_factor", displayName: "Rheumatoid factor (RF)", category: .bloodPanel, canonicalUnit: "IU/mL", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ccp_antibody", displayName: "Cyclic citrullinated peptide antibody (CCP)", category: .bloodPanel, canonicalUnit: "U/mL", decimals: 1, referenceTextHint: fromReport),
        .init(key: "dsdna_antibody", displayName: "Double-stranded DNA antibodies (dsDNA)", category: .bloodPanel, canonicalUnit: "IU/mL", decimals: 0, referenceTextHint: fromReport),
        .init(key: "ttg_antibody", displayName: "Tissue transglutaminase antibody (tTG)", category: .bloodPanel, canonicalUnit: "U/mL", decimals: 1, referenceTextHint: fromReport),
        // Computed ratios many full panels (incl. Superpower) print as their own value row.
        // Baseline never computes these itself — it just records the number the report already gives.
        .init(key: "ldl_hdl_ratio", displayName: "LDL/HDL ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "triglyceride_hdl_ratio", displayName: "Triglyceride/HDL ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "tyg_index", displayName: "TyG index", category: .bloodPanel, canonicalUnit: "score", decimals: 2, referenceTextHint: fromReport),
        .init(key: "neutrophil_lymphocyte_ratio", displayName: "Neutrophil-to-lymphocyte ratio (NLR)", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "platelet_lymphocyte_ratio", displayName: "Platelet-to-lymphocyte ratio (PLR)", category: .bloodPanel, canonicalUnit: "ratio", decimals: 1, referenceTextHint: fromReport),
        .init(key: "monocyte_lymphocyte_ratio", displayName: "Monocyte-to-lymphocyte ratio (MLR)", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "castelli_risk_index_1", displayName: "Castelli risk index I", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "castelli_risk_index_2", displayName: "Castelli risk index II", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "atherogenic_index_plasma", displayName: "Atherogenic index of plasma (AIP)", category: .bloodPanel, canonicalUnit: "score", decimals: 2, referenceTextHint: fromReport),
        .init(key: "ast_alt_ratio", displayName: "AST/ALT ratio (De Ritis ratio)", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "bilirubin_albumin_ratio", displayName: "Bilirubin/albumin ratio", category: .bloodPanel, canonicalUnit: "ratio", decimals: 2, referenceTextHint: fromReport),
        .init(key: "free_androgen_index", displayName: "Free androgen index (FAI)", category: .bloodPanel, canonicalUnit: "%", decimals: 1, referenceTextHint: fromReport),
        // Blood pressure (the paired marker — see LabBookProjection.bpSystolicKey/bpDiastolicKey)
        .init(key: "bp_systolic", displayName: "Blood pressure (systolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "bp_diastolic", displayName: "Blood pressure (diastolic)", category: .bloodPressure, canonicalUnit: "mmHg", decimals: 0, referenceTextHint: fromReport),
        .init(key: "resting_pulse", displayName: "Resting pulse", category: .bloodPressure, canonicalUnit: "bpm", decimals: 0, referenceTextHint: fromReport),
        // Body measurements
        .init(key: "weight", displayName: "Weight", category: .bodyMeasurement, canonicalUnit: "kg", decimals: 1),
        .init(key: "body_fat", displayName: "Body fat", category: .bodyMeasurement, canonicalUnit: "%", decimals: 1),
        .init(key: "waist", displayName: "Waist circumference", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),
        .init(key: "height", displayName: "Height", category: .bodyMeasurement, canonicalUnit: "cm", decimals: 1),
    ]

    /// Fast lookup by key. Built once from `builtIn`.
    private static let byKey: [String: MarkerDefinition] = {
        var m: [String: MarkerDefinition] = [:]
        for d in builtIn { m[d.key] = d }
        return m
    }()

    /// The built-in definition for `key`, or `nil` if it's a custom marker.
    public static func definition(for key: String) -> MarkerDefinition? {
        byKey[key]
    }

    /// Build a definition for a user-added custom marker. Categorised as `.other`
    /// with no reference hint and no direction judgement — the store is never gated
    /// by the built-in dictionary.
    public static func custom(key: String, displayName: String, unit: String, decimals: Int = 1) -> MarkerDefinition {
        MarkerDefinition(
            key: key,
            displayName: displayName,
            category: .other,
            canonicalUnit: unit,
            decimals: decimals,
            referenceTextHint: nil,
            higherIsBetter: nil
        )
    }

    // MARK: - Panel groups (display-only sub-grouping within .bloodPanel)

    /// Purely organisational sub-grouping of the ~120 `.bloodPanel` markers into the same panel
    /// names a Superpower/Quest-style report groups its own results under (Lipids, Metabolic,
    /// Kidney, …) — so a full ~100-marker scan reads like the source report instead of one long
    /// alphabetised list. This is DISPLAY ONLY: it doesn't touch `LabMarkerCategory` (the stored
    /// schema value), carries no reference ranges, and doesn't judge any value — see the
    /// NON-CLINICAL note on `LabMarkerCategory` itself.
    public static let panelGroupOrder: [String] = [
        "Lipids", "Metabolic & glucose", "Complete blood count", "Iron & anemia", "Kidney",
        "Liver & protein", "Electrolytes & minerals", "Thyroid", "Hormones",
        "Vitamins", "Inflammation & immune", "Other",
    ]

    private static let panelGroupByKey: [String: String] = {
        var m: [String: String] = [:]
        func tag(_ group: String, _ keys: [String]) { for k in keys { m[k] = group } }
        tag("Lipids", [
            "total_cholesterol", "ldl", "hdl", "triglycerides", "non_hdl_cholesterol", "apob",
            "apoa1", "lp_a", "cholesterol_hdl_ratio", "ldl_hdl_ratio", "triglyceride_hdl_ratio",
            "castelli_risk_index_1", "castelli_risk_index_2", "atherogenic_index_plasma",
            "oxidized_ldl", "omega_3_index",
        ])
        tag("Metabolic & glucose", [
            "fasting_glucose", "hba1c", "estimated_average_glucose", "fasting_insulin", "homa_ir", "c_peptide", "fructosamine",
            "uric_acid", "tyg_index",
        ])
        tag("Complete blood count", [
            "lymphocyte_pct", "mcv", "rdw", "wbc_count", "rbc_count", "hematocrit",
            "platelet_count", "mch", "mchc", "mpv", "neutrophil_pct", "monocyte_pct",
            "eosinophil_pct", "basophil_pct", "neutrophil_absolute", "lymphocyte_absolute",
            "monocyte_absolute", "eosinophil_absolute", "basophil_absolute",
            "neutrophil_lymphocyte_ratio", "platelet_lymphocyte_ratio", "monocyte_lymphocyte_ratio",
        ])
        tag("Iron & anemia", [
            "ferritin", "iron", "transferrin_saturation", "haemoglobin", "tibc", "transferrin",
            "rbc_folate", "methylmalonic_acid",
        ])
        tag("Kidney", ["egfr", "creatinine", "bun", "bun_creatinine_ratio", "cystatin_c", "cystatin_c_egfr"])
        tag("Liver & protein", [
            "alt", "ast", "ggt", "total_bilirubin", "direct_bilirubin", "indirect_bilirubin", "total_protein",
            "globulin", "ag_ratio", "alkaline_phosphatase", "albumin", "ast_alt_ratio", "bilirubin_albumin_ratio",
        ])
        tag("Electrolytes & minerals", [
            "sodium", "potassium", "calcium", "magnesium", "phosphorus", "chloride", "co2",
            "zinc", "copper", "selenium", "magnesium_rbc", "corrected_calcium",
        ])
        tag("Thyroid", [
            "tsh", "free_t4", "free_t3", "total_t3", "total_t4", "reverse_t3",
            "tpo_antibodies", "thyroglobulin_antibodies", "t3_uptake", "free_t4_index",
        ])
        tag("Hormones", [
            "testosterone_total", "testosterone_free", "testosterone_bioavailable", "shbg", "estradiol", "progesterone",
            "dhea_s", "cortisol", "lh", "fsh", "prolactin", "igf_1", "psa", "free_androgen_index",
        ])
        tag("Vitamins", [
            "vitamin_d", "vitamin_b12", "folate", "vitamin_a", "vitamin_e", "vitamin_k",
            "vitamin_b6", "homocysteine",
        ])
        tag("Inflammation & immune", [
            "crp", "esr", "fibrinogen", "immunoglobulin_a", "immunoglobulin_e", "ana_titer",
            "rheumatoid_factor", "ccp_antibody", "dsdna_antibody", "ttg_antibody", "adma", "sdma",
        ])
        return m
    }()

    /// The display panel group for a `.bloodPanel` key ("Lipids", "Kidney", …), or "Other" for a
    /// custom marker or any built-in key not yet tagged above. `nil` only for keys outside the
    /// blood panel (blood pressure / body measurements already have their own top-level category).
    public static func panelGroup(for key: String) -> String? {
        guard byKey[key] == nil || byKey[key]?.category == .bloodPanel else { return nil }
        return panelGroupByKey[key] ?? "Other"
    }
}
