import Foundation

// BiometricAgeEngine.swift — "Baseline Age": an original, in-house multi-domain biological-age estimate.
//
// WHOOP's "Healthspan"/pace-of-aging figure is undisclosed — no published formula, no visible inputs, no
// way for a user to check the arithmetic. This is the opposite: every domain below is either a DIRECT
// reuse of an already-published reference this codebase carries (Nes 2011 cardiorespiratory model,
// Nunan-style RMSSD-by-age norms already in VitalityEngine) or a transparent, documented combination of
// signals WHOOP's own single number can't show you individually. The combination itself — which domains,
// how they're weighted, the saturating transform — is Baseline's own construction, same honesty rule as
// every other composite in this codebase: real inputs, visible math, no claim of clinical validation.
//
// Five domains, each expressed as a YEARS-EQUIVALENT delta from chronological age (negative = younger):
//   1. Cardiorespiratory — resting HR + activity vs a reference peer (FitnessAgeEngine's own Nes term).
//   2. Autonomic (HRV)   — RMSSD read against VitalityEngine's age-normative curve, inverted to "your HRV
//                          reads like age N".
//   3. Sleep recovery    — duration-vs-need and bed/wake regularity (reuses VitalityEngine's proxies).
//   4. Training balance  — TrainingLoadEngine's Acute:Chronic ratio; both under- and over-reaching cost
//                          years, matching Gabbett's published U-shaped injury-risk curve.
//   5. Respiratory stability — night-to-night respiratory-rate variability; an early, non-specific
//                          stress/illness signal (already used qualitatively by this app's illness
//                          heads-up), scored quantitatively here for the first time.
//
// KEY DESIGN FIX over the existing Fitness Age: that model is perfectly LINEAR, so one extreme input
// (a very low resting HR) can alone swing the estimate to its hard floor with no room left for any other
// signal (the exact "hit exactly 20" complaint this responds to). Here every domain is summed, THEN the
// total is passed through a smooth saturating curve (tanh) — a big raw delta compresses gracefully
// instead of a hard clamp, and no single domain can single-handedly pin the result.
public enum BiometricAgeEngine {

    /// Maximum years-equivalent swing the combined estimate can approach (never quite reach — tanh is
    /// asymptotic). Wider than Fitness Age's own [20,80] absolute clamp because this is a delta bound, not
    /// an absolute one: a 25-year-old with an extreme profile can still read meaningfully young/old
    /// without being forced into the same 20-year floor a 45-year-old would hit.
    public static let maxSwingYears = 22.0

    /// Per-domain cap BEFORE combination — keeps any one domain from dominating the sum outright, so the
    /// tanh saturation reflects genuine multi-domain agreement rather than one runaway input.
    static let perDomainCapYears = 12.0

    public struct Contribution: Equatable, Sendable {
        public let key: String
        public let label: String
        /// Years-equivalent delta this domain alone contributes (before the combined saturating curve).
        public let deltaYears: Double
        public init(key: String, label: String, deltaYears: Double) {
            self.key = key; self.label = label; self.deltaYears = deltaYears
        }
    }

    public struct Result: Equatable, Sendable {
        public let chronoAge: Double
        public let biometricAge: Double
        public let deltaYears: Double          // chronoAge - biometricAge (positive = younger)
        public let contributions: [Contribution]
        public let domainsUsed: Int
        public init(chronoAge: Double, biometricAge: Double, deltaYears: Double,
                    contributions: [Contribution], domainsUsed: Int) {
            self.chronoAge = chronoAge; self.biometricAge = biometricAge; self.deltaYears = deltaYears
            self.contributions = contributions; self.domainsUsed = domainsUsed
        }
    }

    public struct Inputs: Sendable {
        public let chronoAge: Double
        public let sex: String
        public let restingHR: Double?
        public let paIndex: Double?             // FitnessAgeEngine.physicalActivityIndexFromStrain(...)
        public let rmssd: Double?
        public let sleepHours: Double?
        public let sleepNeedHours: Double?
        public let sleepConsistency: Double?    // 0...1 FALLBACK, from VitalityEngine.bedWakeRegularity / sleepConsistency — used only when sriPercent is nil
        /// Preferred sleep-regularity signal: the published Phillips 2017 Sleep Regularity Index (see
        /// SleepRegularityEngine), [-100, 100]. When present this REPLACES `sleepConsistency` for the
        /// sleep-regularity domain — a peer-reviewed, mortality-linked index beats a face-valid proxy.
        public let sriPercent: Double?
        public let trainingLoadRatio: Double?   // TrainingLoadEngine.Result.ratio
        public let respRateCV: Double?          // coefficient of variation of nightly respiratory rate
        public init(chronoAge: Double, sex: String, restingHR: Double?, paIndex: Double?, rmssd: Double?,
                    sleepHours: Double?, sleepNeedHours: Double?, sleepConsistency: Double?,
                    sriPercent: Double? = nil, trainingLoadRatio: Double?, respRateCV: Double?) {
            self.chronoAge = chronoAge; self.sex = sex; self.restingHR = restingHR; self.paIndex = paIndex
            self.rmssd = rmssd; self.sleepHours = sleepHours; self.sleepNeedHours = sleepNeedHours
            self.sleepConsistency = sleepConsistency; self.sriPercent = sriPercent
            self.trainingLoadRatio = trainingLoadRatio
            self.respRateCV = respRateCV
        }
    }

    /// Minimum domains required before a headline number is shown — an honest "not enough signal yet"
    /// rather than a number built almost entirely from one input.
    public static let minDomains = 2

    private static func cap(_ v: Double) -> Double { min(perDomainCapYears, max(-perDomainCapYears, v)) }

    public static func compute(_ inputs: Inputs) -> Result? {
        guard inputs.chronoAge > 0 else { return nil }
        var contributions: [Contribution] = []

        // 1. Cardiorespiratory — the Nes term, reused verbatim, capped before combination.
        if let rhr = inputs.restingHR, rhr > 0 {
            let pai = inputs.paIndex ?? FitnessAgeEngine.paiReference
            let raw = FitnessAgeEngine.rawCardioAgeDeltaYears(sex: inputs.sex, restingHR: rhr, paIndex: pai)
            contributions.append(Contribution(key: "cardio", label: "Resting HR & activity", deltaYears: cap(raw)))
        }

        // 2. Autonomic (HRV) — invert VitalityEngine's own age-normative RMSSD curve: "your HRV reads
        // like age N", delta = that implied age minus your real age.
        if let rmssd = inputs.rmssd, rmssd > 0 {
            let impliedAge = VitalityEngine.ageImpliedByRMSSD(rmssd)
            contributions.append(Contribution(key: "hrv", label: "Heart-rate variability",
                                              deltaYears: cap(impliedAge - inputs.chronoAge)))
        }

        // 3. Sleep recovery — under-sleeping your personal need costs years; poor bed/wake regularity
        // costs a smaller, separate amount (they're not the same failure mode: someone can sleep enough
        // hours at wildly different clock times, or too few hours on a perfectly regular schedule).
        if let hours = inputs.sleepHours, hours > 0 {
            let need = inputs.sleepNeedHours ?? 8.0
            let deficitHours = need - hours
            // ~0.6 yr per hour of nightly deficit, capped by the shared per-domain cap — a rough, openly
            // stated sensitivity, not a published coefficient (no such coefficient exists in the literature
            // for "hours of sleep debt -> biological age").
            let durationDelta = cap(deficitHours * 0.6)
            contributions.append(Contribution(key: "sleep_duration", label: "Sleep vs your need", deltaYears: durationDelta))
        }
        if let sri = inputs.sriPercent {
            // Phillips 2017 SRI: +100 (identical nightly timing) -> 0 delta; 0 (random timing) -> +4
            // years; negative SRI (inverted schedule, e.g. heavy shift work) extrapolates further.
            let regularityDelta = cap((100 - sri) / 100 * 4)
            contributions.append(Contribution(key: "sleep_regularity", label: "Sleep regularity (SRI)", deltaYears: regularityDelta))
        } else if let consistency = inputs.sleepConsistency {
            // Fallback proxy when a real SRI can't be computed (fewer than 4 day-consecutive nights):
            // consistency 1.0 (regular) -> 0 delta; 0.0 (chaotic) -> +4 years.
            let regularityDelta = cap((1 - consistency) * 4)
            contributions.append(Contribution(key: "sleep_regularity", label: "Sleep regularity", deltaYears: regularityDelta))
        }

        // 4. Training load balance — Gabbett's published ACWR curve is U-shaped for injury risk: both
        // detraining (ratio well under 1) and overreaching (ratio well over 1.3) cost something, high load
        // costs materially more than easing off does.
        if let ratio = inputs.trainingLoadRatio {
            let delta: Double
            if ratio >= TrainingLoadEngine.highLoadCeiling {
                delta = cap((ratio - TrainingLoadEngine.highLoadCeiling) * 8 + 2)
            } else if ratio > TrainingLoadEngine.sweetSpotCeiling {
                delta = cap((ratio - TrainingLoadEngine.sweetSpotCeiling) * 4)
            } else if ratio < TrainingLoadEngine.underTrainingCeiling {
                delta = cap((TrainingLoadEngine.underTrainingCeiling - ratio) * 2)
            } else {
                delta = 0
            }
            contributions.append(Contribution(key: "training_load", label: "Training load balance", deltaYears: delta))
        }

        // 5. Respiratory stability — a modest weight; elevated night-to-night respiratory-rate variability
        // is a recognized (if non-specific) early stress/illness marker, not on its own diagnostic.
        if let cv = inputs.respRateCV, cv >= 0 {
            // ~0% CV -> 0 delta; 15%+ CV -> capped at +3 years (deliberately small weight vs the other
            // domains — this is the least individually validated signal here).
            let delta = min(3.0, max(0.0, (cv - 0.03) * 30))
            contributions.append(Contribution(key: "resp_stability", label: "Respiratory stability", deltaYears: delta))
        }

        guard contributions.count >= minDomains else { return nil }

        let totalRaw = contributions.reduce(0) { $0 + $1.deltaYears }
        // Smooth saturating combination: a huge raw sum compresses toward ±maxSwingYears instead of a
        // hard clamp, so multi-domain agreement can still push further than any single domain's own cap.
        let combined = maxSwingYears * tanh(totalRaw / maxSwingYears)
        let bioAge = max(1, inputs.chronoAge + combined)

        return Result(chronoAge: inputs.chronoAge, biometricAge: bioAge, deltaYears: -combined,
                      contributions: contributions.sorted { $0.deltaYears < $1.deltaYears },
                      domainsUsed: contributions.count)
    }
}
