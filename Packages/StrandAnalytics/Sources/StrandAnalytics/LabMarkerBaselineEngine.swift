import Foundation

// LabMarkerBaselineEngine.swift — a PERSONAL baseline for one Lab Book marker, built entirely
// from the user's own prior readings. This is deliberately NOT a clinical reference range: it
// never asserts what's medically normal, only whether the newest reading is typical for THIS
// person compared to their own history — the same self-referential idea "Baseline" already uses
// for Baseline Age, HR/HRV, etc. No population data, no shipped ranges, nothing to maintain.
//
// Cold start is honest: with fewer than `minimumPriorReadings` readings before the latest one,
// `evaluate` returns nil (the caller shows "building your baseline" rather than a guess).
public enum LabMarkerBaselineEngine {

    public enum Status: Sendable, Equatable {
        case muchLower, lower, typical, higher, muchHigher
    }

    public struct Result: Sendable, Equatable {
        /// Mean of the PRIOR readings (excludes the latest).
        public let mean: Double
        /// Population stdev of the prior readings (0 when every prior reading was identical).
        public let stdev: Double
        public let latest: Double
        /// (latest - mean) / effective stdev. Effective stdev floors at 1% of |mean| so an
        /// all-identical history doesn't divide by zero — a genuinely new value still registers.
        public let zScore: Double
        public let status: Status
        /// Latest reading as a 0...1 fraction of a fixed ±2.5σ display window, for TypicalRangeBar.
        public let valueFraction: Double
        /// The ±1σ "typical for you" band as the same 0...1 fraction, for TypicalRangeBar's hatch.
        public let typicalFraction: ClosedRange<Double>
    }

    /// Prior readings required before a baseline is computed (excludes the latest itself).
    /// 3 keeps the z-score from being whiplashed by a single outlier while still being reachable
    /// after a handful of panels.
    public static let minimumPriorReadings = 3

    /// `history` oldest-first; the LAST element is the reading being evaluated against everything
    /// before it. Returns nil until at least `minimumPriorReadings` earlier readings exist.
    public static func evaluate(history: [Double]) -> Result? {
        guard history.count >= minimumPriorReadings + 1 else { return nil }
        let latest = history[history.count - 1]
        let prior = Array(history.dropLast())
        let n = Double(prior.count)
        let mean = prior.reduce(0, +) / n
        let variance = prior.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let stdev = variance.squareRoot()
        let effectiveStdev = stdev > 0 ? stdev : max(abs(mean) * 0.01, 0.0001)

        let z = (latest - mean) / effectiveStdev
        let status: Status
        switch z {
        case ..<(-1.5): status = .muchLower
        case -1.5..<(-0.5): status = .lower
        case -0.5...0.5: status = .typical
        case 0.5..<1.5: status = .higher
        default: status = .muchHigher
        }

        let lo = mean - 2.5 * effectiveStdev
        let hi = mean + 2.5 * effectiveStdev
        let span = max(hi - lo, 0.0001)
        func frac(_ v: Double) -> Double { min(max((v - lo) / span, 0), 1) }
        let band = frac(mean - effectiveStdev)...frac(mean + effectiveStdev)

        return Result(mean: mean, stdev: stdev, latest: latest, zScore: z, status: status,
                      valueFraction: frac(latest), typicalFraction: band)
    }
}
