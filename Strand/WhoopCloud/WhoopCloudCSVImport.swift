import Foundation
import StrandAnalytics
import StrandImport

// MARK: - WHOOP manual export ("Settings -> Download data") — one-time historical backfill
//
// The manual CSV export (`physiological_cycles.csv`) carries the SAME cloud-computed numbers the
// v2 API exposes (recovery %, RHR, HRV, strain, sleep performance, SpO2, skin temp) — it is not an
// independent source, just a bulk point-in-time dump of the same WHOOP-side truth. Its only real
// value here is reaching further back than the live API sync's rolling window, so this importer
// builds a SEPARATE historical report rather than merging into the live comparison: the two never
// share a code path or a persisted store, so there is no way for a live day and an imported day to
// blend and mask a genuine discrepancy. If a date range happens to be covered by both, that's fine —
// they're shown as two distinct reports, never combined into one set of numbers.
public enum WhoopCloudCSVImport {

    public enum ImportError: LocalizedError {
        case unreadable
        case noHeader
        case noRows

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "Couldn't read that file as text."
            case .noHeader: return "That doesn't look like a WHOOP physiological_cycles.csv export (no header row)."
            case .noRows: return "No cycle rows found in that file."
            }
        }
    }

    /// Parses a `physiological_cycles.csv` (from WHOOP's Settings -> "Get your data" export) into
    /// per-day cloud values, keyed the same way the live API path keys them (the device's LOCAL
    /// calendar day of the cycle's start time, matching Baseline's own DailyMetric.day convention),
    /// so the two are drop-in compatible with `WhoopCloudComparisonEngine`.
    public static func parseCloudDays(csv: String) throws -> [String: CloudDayValues] {
        var lines = csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { throw ImportError.noHeader }
        let header = lines.removeFirst().components(separatedBy: ",")
        guard !lines.isEmpty else { throw ImportError.noRows }

        func index(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let startIdx = index("Cycle start time") else { throw ImportError.noHeader }
        let recoveryIdx = index("Recovery score %")
        let rhrIdx = index("Resting heart rate (bpm)")
        let hrvIdx = index("Heart rate variability (ms)")
        let strainIdx = index("Day Strain")
        let sleepPerfIdx = index("Sleep performance %")

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"

        var result: [String: CloudDayValues] = [:]
        for line in lines {
            let cols = line.components(separatedBy: ",")
            guard cols.count > startIdx, let start = dayFormatter.date(from: cols[startIdx]) else { continue }
            let day = dayKeyFormatter.string(from: start)

            func double(_ idx: Int?) -> Double? {
                guard let idx, cols.count > idx else { return nil }
                return Double(cols[idx])
            }

            result[day] = CloudDayValues(
                restingHr: double(rhrIdx), hrv: double(hrvIdx), recovery: double(recoveryIdx),
                strain: WhoopExportImporter.effortFromImportedDayStrain(double(strainIdx)),
                sleepPerformance: double(sleepPerfIdx))
        }
        guard !result.isEmpty else { throw ImportError.noRows }
        return result
    }

    /// Reads the file at `url` (a `.csv` picked directly, or extracted by the caller from the zip
    /// WHOOP emails) and parses it. Throws `ImportError.unreadable` for anything not valid UTF-8 text.
    public static func parseCloudDays(fileAt url: URL) throws -> [String: CloudDayValues] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw ImportError.unreadable }
        return try parseCloudDays(csv: text)
    }
}
