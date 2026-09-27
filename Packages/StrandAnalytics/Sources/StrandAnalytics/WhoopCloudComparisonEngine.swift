import Foundation

// MARK: - WHOOP Cloud vs Baseline comparison
//
// Pure math, no networking: takes Baseline's own locally-computed daily rows (WhoopStore's
// `DailyMetric`) and WHOOP's own cloud-reported per-day numbers for the SAME strap, matches them by
// day, and reports per-metric differences. Used to (a) validate Baseline's own algorithms against
// WHOOP's published ones, (b) find concrete discrepancies worth investigating as possible Baseline
// improvements, and (c) judge which source reads as more internally consistent day to day.

public struct WhoopCloudDayComparison {
    public let day: String

    public let baselineRestingHr: Double?
    public let cloudRestingHr: Double?
    public let baselineHrv: Double?
    public let cloudHrv: Double?
    public let baselineRecovery: Double?
    public let cloudRecovery: Double?
    public let baselineStrain: Double?
    public let cloudStrain: Double?
    public let baselineSleepPerformance: Double?
    public let cloudSleepPerformance: Double?

    public init(day: String, baselineRestingHr: Double?, cloudRestingHr: Double?, baselineHrv: Double?,
                cloudHrv: Double?, baselineRecovery: Double?, cloudRecovery: Double?, baselineStrain: Double?,
                cloudStrain: Double?, baselineSleepPerformance: Double?, cloudSleepPerformance: Double?) {
        self.day = day
        self.baselineRestingHr = baselineRestingHr
        self.cloudRestingHr = cloudRestingHr
        self.baselineHrv = baselineHrv
        self.cloudHrv = cloudHrv
        self.baselineRecovery = baselineRecovery
        self.cloudRecovery = cloudRecovery
        self.baselineStrain = baselineStrain
        self.cloudStrain = cloudStrain
        self.baselineSleepPerformance = baselineSleepPerformance
        self.cloudSleepPerformance = cloudSleepPerformance
    }
}

/// Rollup for one metric across every matched day in the window.
public struct WhoopMetricComparison {
    public let metric: String
    /// Positive = Baseline reads higher than WHOOP cloud, on average.
    public let meanSignedDiff: Double
    public let meanAbsDiff: Double
    public let matchedDays: Int
    /// Day-to-day standard deviation of each source's OWN value, used to judge which source is
    /// noisier / more internally consistent (not which is "more correct" — we have no ground truth).
    public let baselineStdDev: Double
    public let cloudStdDev: Double
}

public struct WhoopCloudComparisonReport {
    public let windowStart: String
    public let windowEnd: String
    public let metrics: [WhoopMetricComparison]
    public let days: [WhoopCloudDayComparison]

    public init(windowStart: String, windowEnd: String, metrics: [WhoopMetricComparison], days: [WhoopCloudDayComparison]) {
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.metrics = metrics
        self.days = days
    }

    /// Human-readable one-liners the UI can render as-is, e.g. "HRV: Baseline reads 3.2ms lower
    /// than WHOOP on average" plus a note on which source is steadier day to day.
    public var summaryLines: [String] {
        metrics.map { m in
            let direction = m.meanSignedDiff > 0 ? "higher" : (m.meanSignedDiff < 0 ? "lower" : "the same")
            let steadier = m.baselineStdDev < m.cloudStdDev ? "Baseline" : (m.cloudStdDev < m.baselineStdDev ? "WHOOP cloud" : "neither")
            return "\(m.metric): Baseline reads \(String(format: "%.1f", abs(m.meanSignedDiff))) \(direction) than WHOOP on average across \(m.matchedDays) matched day(s); \(steadier) is the steadier day-to-day source."
        }
    }
}

public enum WhoopCloudComparisonEngine {

    /// Builds the full report from parallel arrays: Baseline's own daily rows and WHOOP's cloud
    /// records for the same date range, already mapped to plain per-day dictionaries by the caller
    /// (the networking/model layer lives outside this pure-math module).
    public static func compare(
        baselineDays: [String: BaselineDayValues],
        cloudDays: [String: CloudDayValues]
    ) -> WhoopCloudComparisonReport {
        let matchedDayKeys = Set(baselineDays.keys).intersection(cloudDays.keys).sorted()

        let days: [WhoopCloudDayComparison] = matchedDayKeys.map { day in
            let b = baselineDays[day]!
            let c = cloudDays[day]!
            return WhoopCloudDayComparison(
                day: day,
                baselineRestingHr: b.restingHr, cloudRestingHr: c.restingHr,
                baselineHrv: b.hrv, cloudHrv: c.hrv,
                baselineRecovery: b.recovery, cloudRecovery: c.recovery,
                baselineStrain: b.strain, cloudStrain: c.strain,
                baselineSleepPerformance: b.sleepPerformance, cloudSleepPerformance: c.sleepPerformance)
        }

        func metric(_ name: String, _ baseline: (WhoopCloudDayComparison) -> Double?, _ cloud: (WhoopCloudDayComparison) -> Double?) -> WhoopMetricComparison? {
            let pairs = days.compactMap { d -> (Double, Double)? in
                guard let b = baseline(d), let c = cloud(d) else { return nil }
                return (b, c)
            }
            guard !pairs.isEmpty else { return nil }
            let signedDiffs = pairs.map { $0.0 - $0.1 }
            let absDiffs = signedDiffs.map { abs($0) }
            let baselineValues = pairs.map { $0.0 }
            let cloudValues = pairs.map { $0.1 }
            return WhoopMetricComparison(
                metric: name,
                meanSignedDiff: signedDiffs.reduce(0, +) / Double(signedDiffs.count),
                meanAbsDiff: absDiffs.reduce(0, +) / Double(absDiffs.count),
                matchedDays: pairs.count,
                baselineStdDev: stdDev(baselineValues),
                cloudStdDev: stdDev(cloudValues))
        }

        let metrics = [
            metric("Resting HR", { $0.baselineRestingHr }, { $0.cloudRestingHr }),
            metric("HRV", { $0.baselineHrv }, { $0.cloudHrv }),
            metric("Recovery", { $0.baselineRecovery }, { $0.cloudRecovery }),
            metric("Strain", { $0.baselineStrain }, { $0.cloudStrain }),
            metric("Sleep performance", { $0.baselineSleepPerformance }, { $0.cloudSleepPerformance }),
        ].compactMap { $0 }

        return WhoopCloudComparisonReport(
            windowStart: matchedDayKeys.first ?? "", windowEnd: matchedDayKeys.last ?? "",
            metrics: metrics, days: days)
    }

    private static func stdDev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }
}

/// Baseline's own per-day numbers, already extracted from `DailyMetric` by the caller.
public struct BaselineDayValues {
    public let restingHr: Double?
    public let hrv: Double?
    public let recovery: Double?
    public let strain: Double?
    public let sleepPerformance: Double?

    public init(restingHr: Double?, hrv: Double?, recovery: Double?, strain: Double?, sleepPerformance: Double?) {
        self.restingHr = restingHr
        self.hrv = hrv
        self.recovery = recovery
        self.strain = strain
        self.sleepPerformance = sleepPerformance
    }
}

/// WHOOP cloud's per-day numbers, already extracted from the raw API records by the caller.
public struct CloudDayValues {
    public let restingHr: Double?
    public let hrv: Double?
    public let recovery: Double?
    public let strain: Double?
    public let sleepPerformance: Double?

    public init(restingHr: Double?, hrv: Double?, recovery: Double?, strain: Double?, sleepPerformance: Double?) {
        self.restingHr = restingHr
        self.hrv = hrv
        self.recovery = recovery
        self.strain = strain
        self.sleepPerformance = sleepPerformance
    }
}
