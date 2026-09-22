import Foundation

// HRRecoveryEngine.swift — heart-rate recovery after exercise, a genuinely new signal from data the app
// already stores but never scored (raw per-second HR samples in the minutes after a workout ends).
//
// Cole CR, Blackstone EH, Pashkow FJ, Snader CE, Lauer MS. "Heart-Rate Recovery Immediately after
// Exercise as a Predictor of Mortality." N Engl J Med. 1999;341(18):1351-1357. Found that a SMALLER drop
// in heart rate during the first minute after peak exercise (abnormal HRR) independently predicted
// all-cause mortality in a large treadmill-test cohort, controlling for other risk factors — a faster
// drop reflects healthier parasympathetic (vagal) reactivation.
//
// IMPORTANT SCOPE LIMIT, stated plainly: Cole's cohort and its specific "≤12 bpm = abnormal" cutoff were
// measured on a STANDARDIZED graded treadmill protocol immediately at peak exertion. A free-living workout
// (irregular effort, no fixed peak protocol) is a different measurement context, so this deliberately does
// NOT import that clinical cutoff or claim a mortality-risk classification. What transfers is the
// underlying physiological concept — a bigger HR drop in the first 60s after exercise stops is a real,
// well-established marker of cardiovascular fitness — used here DIRECTIONALLY (bigger drop = better),
// not as a diagnostic threshold.
public enum HRRecoveryEngine {
    /// Recovery is only meaningful after a REAL exertion bout: too short or too easy a "workout" never
    /// raised heart rate enough for a recovery slope to mean anything.
    public static let minWorkoutDurationSec = 180
    public static let minPeakBpmAboveRestAtStart = 20

    /// Accept a post-workout HR sample as "the 60s reading" only within this tolerance window — a strap
    /// dropping a beat or two near the mark shouldn't disqualify the read entirely, but a sample from
    /// minutes later would silently understate true recovery.
    public static let toleranceSec = 20

    public struct Sample: Sendable { public let ts: Int; public let bpm: Int
        public init(ts: Int, bpm: Int) { self.ts = ts; self.bpm = bpm } }

    /// HRR60 (bpm): heart rate at workout end minus heart rate ~60s later. Returns nil when there isn't
    /// a real exertion bout, or no sample lands close enough to the 60s mark to trust.
    /// - Parameters:
    ///   - endTs: the workout's end timestamp (unix seconds).
    ///   - durationSec: the workout's duration — gates out trivial/very short bouts.
    ///   - hrAtEnd: heart rate at (or immediately before) `endTs`.
    ///   - postSamples: HR samples AFTER `endTs`, any order, ideally spanning through +90s.
    public static func hrr60(endTs: Int, durationSec: Double, hrAtEnd: Int, postSamples: [Sample]) -> Double? {
        guard durationSec >= Double(minWorkoutDurationSec) else { return nil }
        let target = endTs + 60
        guard let nearest = postSamples.min(by: { abs($0.ts - target) < abs($1.ts - target) }),
              abs(nearest.ts - target) <= toleranceSec else { return nil }
        return Double(hrAtEnd - nearest.bpm)
    }

    /// Plain-language band for the UI — directional only, no clinical claim (see header).
    public enum Band: String, Sendable {
        case strong     // >= 30 bpm drop
        case typical    // 18..<30
        case sluggish   // < 18
        public var label: String {
            switch self {
            case .strong:   return "Strong recovery"
            case .typical:  return "Typical recovery"
            case .sluggish: return "Sluggish recovery"
            }
        }
    }
    public static func band(_ hrr60: Double) -> Band {
        if hrr60 >= 30 { return .strong }
        if hrr60 >= 18 { return .typical }
        return .sluggish
    }
}
