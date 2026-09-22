import Foundation

// TrainingLoadEngine.swift — Acute:Chronic Workload Ratio (ACWR), a published sports-science measure
// of whether recent training load is ramping up faster than the body has adapted to.
//
// Gabbett (2016, Br J Sports Med) and the training-load literature it summarizes: divide the mean load
// over the last 7 days (acute) by the mean load over the last 28 days (chronic, which already includes
// the acute window). A ratio near 1.0 means this week matches your recent norm; a ratio pushed well
// above 1.0 means load is climbing faster than the body has had time to adapt to, which several large
// cohort studies (rugby, Australian football, distance running) associate with a higher injury rate.
// This is NOT medical advice and not a guarantee — it is a published, honest heuristic, same spirit as
// every other approximate score in this app.
//
// "Load" here is Baseline's own daily Effort/Strain score (0–100), the same cardiovascular-load figure
// already computed for every scored day — no new raw-data dependency, this is purely a rolling-average
// read of a number the app already has.
public enum TrainingLoadEngine {

    /// Below this ratio, load is meaningfully lower than the recent norm (detraining / easing off).
    public static let underTrainingCeiling: Double = 0.8
    /// The published "sweet spot" upper bound (0.8–1.3): load is rising in step with recent adaptation.
    public static let sweetSpotCeiling: Double = 1.3
    /// Above this, load is climbing fast enough that Gabbett's cohort data associates it with
    /// materially higher injury rates ("danger zone").
    public static let highLoadCeiling: Double = 1.5

    /// Plain-language read of a computed ratio, gated to whole, honest categories (never a fabricated
    /// precision the underlying data doesn't support).
    public enum Tier: String, Sendable {
        case low        // < underTrainingCeiling
        case balanced   // sweet spot
        case elevated   // between sweetSpotCeiling and highLoadCeiling
        case high       // >= highLoadCeiling

        public var label: String {
            switch self {
            case .low:      return "Low load"
            case .balanced: return "Balanced"
            case .elevated: return "Elevated"
            case .high:     return "High load"
            }
        }
    }

    public struct Result: Sendable, Equatable {
        /// Mean daily Effort/Strain (0–100) over the trailing 7 days.
        public let acute: Double
        /// Mean daily Effort/Strain (0–100) over the trailing 28 days (includes the acute window).
        public let chronic: Double
        /// acute / chronic. 1.0 = this week matches your last month's norm.
        public let ratio: Double
        public let tier: Tier

        public init(acute: Double, chronic: Double, ratio: Double, tier: Tier) {
            self.acute = acute; self.chronic = chronic; self.ratio = ratio; self.tier = tier
        }
    }

    /// Classify a raw ratio into a plain-language tier. `public` so a caller that only has the
    /// PERSISTED ratio (e.g. a UI reading it back from metricSeries, not re-running `compute` over the
    /// full daily series) can still show the same honest label `compute` itself would have produced.
    public static func tier(for ratio: Double) -> Tier {
        if ratio < underTrainingCeiling { return .low }
        if ratio <= sweetSpotCeiling { return .balanced }
        if ratio < highLoadCeiling { return .elevated }
        return .high
    }

    /// Minimum number of the trailing 7 days that must carry a real Effort/Strain value for the acute
    /// window to be trusted (a week with only 1–2 scored days is too sparse to call "this week's load").
    public static let minAcuteDays = 4
    /// Minimum number of the trailing 28 days that must carry a real value for the chronic baseline to
    /// be trusted (half the window, so a newly-active user isn't compared against mostly-missing history).
    public static let minChronicDays = 14

    /// Compute the ratio from a chronological (oldest→newest) series of daily Effort/Strain values
    /// (nil = no score that day, skipped rather than treated as zero load — a rest day with a real
    /// score of low strain is very different from a day with NO data at all). Returns nil when either
    /// window doesn't meet its minimum coverage, or the chronic mean is ~0 (division safety) — an honest
    /// "not enough data yet" rather than a fabricated ratio.
    public static func compute(dailyStrain: [Double?]) -> Result? {
        let acuteWindow = dailyStrain.suffix(7).compactMap { $0 }
        let chronicWindow = dailyStrain.suffix(28).compactMap { $0 }
        guard acuteWindow.count >= minAcuteDays, chronicWindow.count >= minChronicDays else { return nil }
        let acute = acuteWindow.reduce(0, +) / Double(acuteWindow.count)
        let chronic = chronicWindow.reduce(0, +) / Double(chronicWindow.count)
        guard chronic > 1.0 else { return nil }   // avoid a near-zero-denominator blowup on an all-rest month
        let ratio = acute / chronic
        return Result(acute: acute, chronic: chronic, ratio: ratio, tier: tier(for: ratio))
    }
}
