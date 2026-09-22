import Foundation

// SleepRegularityEngine.swift — the published Sleep Regularity Index (SRI), not a house-made proxy.
//
// Phillips AJK, Clerx WM, O'Brien CS, et al. "Irregular sleep/wake patterns are associated with poorer
// academic performance and delayed circadian and sleep/wake timing." Sci Rep 7, 3216 (2017). Definition:
// the probability of being in the SAME sleep/wake state at any two clock-times 24h apart, averaged across
// every pair of consecutive days and every time-of-day bin, rescaled to [-100, 100] (+100 = identical
// sleep timing every night, 0 = random, -100 = perfectly inverted). Lucey et al. and a 2023 eLife UK
// Biobank analysis ("Sleep regularity and mortality: a prospective analysis in the UK Biobank") link a
// LOW SRI to higher all-cause mortality independent of sleep duration — i.e. genuine outcome-linked
// evidence, not just a face-valid consistency heuristic.
//
// This is the SINGLE-BOUT simplification of the index: each night is one bed→wake clock-time window
// rather than full multi-epoch sleep/wake staging (the original paper and its GGIR/sleepreg reference
// implementations use minute-by-minute actigraphy state). That's the standard fallback actigraphy
// research uses whenever only sleep onset/offset timestamps are available rather than continuous
// epoch-level staging — still the same underlying formula, just computed against a coarser sleep/wake
// series. Do not present this as identical to a full-epoch SRI from a research-grade actigraph.
public enum SleepRegularityEngine {
    public struct NightWindow: Sendable {
        public let bedLocalSec: Int    // clock-time of sleep onset, seconds since local midnight [0, 86400)
        public let wakeLocalSec: Int   // clock-time of wake, seconds since local midnight [0, 86400)
        public init(bedLocalSec: Int, wakeLocalSec: Int) {
            self.bedLocalSec = bedLocalSec; self.wakeLocalSec = wakeLocalSec
        }
    }

    /// Minimum consecutive-night PAIRS required — the original paper computes over full weeks; this
    /// floor is a much lower bar so an on-device estimate can appear well before a full week of paired
    /// nights exists, same "estimate at lower confidence, don't just withhold it" posture as elsewhere.
    public static let minPairs = 3

    /// `nights` MUST be in chronological, DAY-CONSECUTIVE order (caller drops any night that isn't
    /// immediately followed by the next calendar day — comparing across a gap night would compare two
    /// unrelated schedules and silently corrupt the index). Returns SRI in [-100, 100], or nil if fewer
    /// than `minPairs` valid consecutive-day pairs are available.
    public static func sri(nights: [NightWindow], binMinutes: Int = 30) -> Double? {
        guard nights.count >= minPairs + 1 else { return nil }
        let binSec = binMinutes * 60
        guard binSec > 0, 86_400 % binSec == 0 else { return nil }
        let binsPerDay = 86_400 / binSec

        func isAsleep(_ night: NightWindow, atBinStart t: Int) -> Bool {
            let bed = night.bedLocalSec, wake = night.wakeLocalSec
            if wake > bed { return t >= bed && t < wake }
            if wake < bed { return t >= bed || t < wake }   // wraps past midnight
            return false                                     // bed == wake: a degenerate/zero-length night
        }

        var agreements = 0
        var total = 0
        for i in 0..<(nights.count - 1) {
            let a = nights[i], b = nights[i + 1]
            for binIdx in 0..<binsPerDay {
                let t = binIdx * binSec
                if isAsleep(a, atBinStart: t) == isAsleep(b, atBinStart: t) { agreements += 1 }
                total += 1
            }
        }
        guard total > 0 else { return nil }
        return -100.0 + 200.0 * Double(agreements) / Double(total)
    }
}
