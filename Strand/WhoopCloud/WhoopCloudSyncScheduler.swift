import Foundation
import WhoopStore
import StrandAnalytics
#if os(iOS)
import BackgroundTasks
#endif

/// PRIVATE personal validation tool (see WhoopCloudCompareView.swift's header). Mirrors
/// `ScheduledDebugExport`'s shape exactly: opt-in, default OFF, Daily/Weekly interval, macOS
/// foreground timer vs iOS best-effort `BGAppRefreshTask`, plus an always-works "Sync now".
///
/// "Auto-connect": once `WhoopCloudAuthStore.isConnected` is true (one completed OAuth login),
/// every scheduled or manual sync silently refreshes the access token via `WhoopCloudAPI` — no
/// re-login prompt ever appears again, matching the user's ask for something that "just reconnects."
@MainActor
public enum WhoopCloudSyncScheduler {

    public enum Interval: String, CaseIterable {
        case daily, weekly
        var days: Int { self == .daily ? 1 : 7 }
    }

    private enum K {
        static let enabled = "whoopCloud.sync.enabled"
        static let interval = "whoopCloud.sync.interval"
        static let lastRunAt = "whoopCloud.sync.lastRunAt"
        static let lastReportSummary = "whoopCloud.sync.lastReportSummary"
    }

    public static let bgTaskIdentifier = "com.noopapp.noop.whoopcloudsync"

    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: K.enabled) }

    public static var interval: Interval {
        Interval(rawValue: UserDefaults.standard.string(forKey: K.interval) ?? "") ?? .weekly
    }

    public static var lastRunAt: Date? {
        let v = UserDefaults.standard.double(forKey: K.lastRunAt)
        return v > 0 ? Date(timeIntervalSince1970: v) : nil
    }

    /// The last comparison report's human-readable lines, persisted so the UI has something to show
    /// immediately on launch without waiting for a fresh sync.
    public static var lastReportLines: [String] {
        (UserDefaults.standard.array(forKey: K.lastReportSummary) as? [String]) ?? []
    }

    // MARK: - Settings screen calls these

    public static func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: K.enabled)
        if on {
            scheduleNext()
        } else {
            cancel()
        }
    }

    public static func setInterval(_ value: Interval) {
        UserDefaults.standard.set(value.rawValue, forKey: K.interval)
        if isEnabled { scheduleNext() }
    }

    /// Call at app launch and whenever the settings screen appears, mirroring `ScheduledDebugExport`.
    public static func activateIfEnabled() {
        guard isEnabled else { return }
        scheduleNext()
        Task { await catchUpIfDue() }
    }

    /// The "Sync now" button — always runs immediately regardless of schedule, and reports errors to
    /// the caller (Settings toggle path swallows and just reschedules; the button surfaces them).
    @discardableResult
    public static func runNow(deviceId: String, store: WhoopStore) async throws -> WhoopCloudComparisonReport {
        try await performSync(deviceId: deviceId, store: store)
    }

    // MARK: - Scheduling (identical shape to ScheduledDebugExport)

    private static var macTimer: DispatchSourceTimer?

    private static func scheduleNext() {
        #if os(macOS)
        macTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + secondsUntilNextRun())
        timer.setEventHandler {
            guard isEnabled else { return }
            Task { @MainActor in
                await runScheduledIfConnected()
                scheduleNext()
            }
        }
        timer.resume()
        macTimer = timer
        #elseif os(iOS)
        submitBackgroundRequest()
        #endif
    }

    private static func cancel() {
        #if os(macOS)
        macTimer?.cancel()
        macTimer = nil
        #elseif os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
        #endif
    }

    private static func catchUpIfDue() async {
        guard isEnabled, secondsUntilNextRun() <= 0 else { return }
        await runScheduledIfConnected()
    }

    private static func secondsUntilNextRun() -> TimeInterval {
        guard let last = lastRunAt else { return 0 }
        let dueAt = last.addingTimeInterval(TimeInterval(interval.days * 24 * 60 * 60))
        return max(0, dueAt.timeIntervalSinceNow)
    }

    /// Runs a scheduled sync only if a connection already exists — a background tick must never
    /// surface a login sheet. A disconnected schedule just waits for the user to hit "Connect".
    private static func runScheduledIfConnected() async {
        guard WhoopCloudAuthStore.isConnected else { return }
        guard let deviceId = currentDeviceRegistryId(), let store = await currentStore() else { return }
        _ = try? await performSync(deviceId: deviceId, store: store)
    }

    // MARK: - The sync itself

    private static func performSync(deviceId: String, store: WhoopStore) async throws -> WhoopCloudComparisonReport {
        // Cover everything since the last successful sync, not just a fixed 3/10-day window — a long
        // gap (app closed for weeks, a missed background run) or the very first sync ever would
        // otherwise silently skip real history that's available on both sides. `minDays` is the floor
        // (a small overlap so a slightly-late scheduled run still re-covers its own last window); a
        // first-ever sync (no `lastRunAt`) pulls a full year so historical data isn't left out.
        let minDays = interval.days == 1 ? 3 : 10
        let days: Int
        if let last = lastRunAt {
            let elapsedDays = Int(Date().timeIntervalSince(last) / 86_400) + 2
            days = max(minDays, elapsedDays)
        } else {
            days = 365
        }

        async let cycles = WhoopCloudAPI.recentCycles(days: days)
        async let recoveries = WhoopCloudAPI.recentRecoveries(days: days)
        async let sleeps = WhoopCloudAPI.recentSleep(days: days)
        let (cloudCycles, cloudRecoveries, cloudSleeps) = try await (cycles, recoveries, sleeps)

        let cloudDays = mergeCloudDays(cycles: cloudCycles, recoveries: cloudRecoveries, sleeps: cloudSleeps)
        guard let fromDay = cloudDays.keys.min(), let toDay = cloudDays.keys.max() else {
            let empty = WhoopCloudComparisonReport(windowStart: "", windowEnd: "", metrics: [], days: [])
            persistReport(empty)
            return empty
        }

        // IntelligenceEngine's computed write target NEVER follows the active strap — it stays
        // permanently on the canonical "my-whoop" id so a remove/re-add never orphans history
        // (Repository.swift's #814 union-model comment, IntelligenceEngine.swift:157-160). A real
        // paired strap's `deviceId` is actually "whoop-<BLE-uuid>" (AddDeviceWizard.swift), so reading
        // ONLY `deviceId + "-noop"` finds zero rows for virtually every real install — the sync
        // reports success (WHOOP's cloud data came back fine) but the comparison is always empty.
        // Union both ids, active strap first, exactly like Repository.unionComputedDailyMetrics.
        let activeComputedId = deviceId + "-noop"
        let canonicalComputedId = Repository.whoopSource + "-noop"
        let computedIds = activeComputedId == canonicalComputedId ? [activeComputedId] : [activeComputedId, canonicalComputedId]

        var localRowsByDay: [String: DailyMetric] = [:]
        var sleepPerfByDay: [String: Double] = [:]
        for id in computedIds {
            for row in (try? await store.dailyMetrics(deviceId: id, from: fromDay, to: toDay)) ?? [] where localRowsByDay[row.day] == nil {
                localRowsByDay[row.day] = row
            }
            // Baseline's own "sleep_performance" (duration-vs-need composite) lives in the long-format
            // metric series, NOT on the DailyMetric row — `row.efficiency` is a genuinely different WHOOP
            // metric (time-asleep / time-in-bed) and comparing it against WHOOP's own
            // sleep_performance_percentage would silently misreport a metric mismatch as a real
            // discrepancy. See AnalyticsEngine.swift's Rest composite / WidgetPublish.swift's
            // `exploreSeries(key: "sleep_performance", source: "my-whoop")` for the same series read
            // through the full Repository merge; this is the raw-store equivalent since the scheduler
            // only has a `WhoopStore` handle, not the full `Repository`.
            for point in (try? await store.metricSeries(deviceId: id, key: "sleep_performance", from: fromDay, to: toDay)) ?? [] where sleepPerfByDay[point.day] == nil {
                sleepPerfByDay[point.day] = point.value
            }
        }

        var baselineDays: [String: BaselineDayValues] = [:]
        for (day, row) in localRowsByDay {
            baselineDays[day] = BaselineDayValues(
                restingHr: row.restingHr.map(Double.init), hrv: row.avgHrv, recovery: row.recovery,
                strain: row.strain, sleepPerformance: sleepPerfByDay[day])
        }
        for (day, perf) in sleepPerfByDay where baselineDays[day] == nil {
            baselineDays[day] = BaselineDayValues(restingHr: nil, hrv: nil, recovery: nil, strain: nil, sleepPerformance: perf)
        }

        let report = WhoopCloudComparisonEngine.compare(baselineDays: baselineDays, cloudDays: cloudDays)
        persistReport(report)
        return report
    }

    private static func mergeCloudDays(cycles: [WhoopCloud.Cycle], recoveries: [WhoopCloud.Recovery],
                                       sleeps: [WhoopCloud.SleepActivity]) -> [String: CloudDayValues] {
        // WHOOP's v2 timestamps carry fractional seconds (e.g. "2026-07-28T00:29:59.000Z"), which the
        // default ISO8601DateFormatter options silently fail to parse, so BOTH variants are tried.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        // Baseline's own DailyMetric.day is keyed by the DEVICE'S LOCAL calendar day (Repository.swift's
        // `dayKeyFormatter` never sets `timeZone`, so it defaults to TimeZone.current) — forcing UTC
        // here meant every night rolled to a different calendar date than Baseline's own row for
        // anyone not literally in UTC, so days almost never matched even when both sides had real data
        // for the same night. Match Baseline's convention: local time zone, no override.
        func dayKey(_ iso: String) -> String? {
            guard let date = withFractional.date(from: iso) ?? whole.date(from: iso) else { return nil }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }

        var strainByDay: [String: Double] = [:]
        for c in cycles {
            guard let day = dayKey(c.start), c.scoreState == "SCORED", let strain = c.score?.strain else { continue }
            strainByDay[day] = strain
        }

        var recoveryByDay: [String: (recovery: Double?, hrv: Double?, rhr: Double?)] = [:]
        let cycleStartById = Dictionary(uniqueKeysWithValues: cycles.map { ($0.id, $0.start) })
        for r in recoveries {
            guard r.scoreState == "SCORED", let start = cycleStartById[r.cycleId], let day = dayKey(start) else { continue }
            recoveryByDay[day] = (r.score?.recoveryScore, r.score?.hrvRmssdMilli, r.score?.restingHeartRate)
        }

        var sleepByDay: [String: Double] = [:]
        for s in sleeps where !s.nap {
            guard let day = dayKey(s.end), s.scoreState == "SCORED",
                  let perf = s.score?.sleepPerformancePercentage else { continue }
            sleepByDay[day] = perf
        }

        var result: [String: CloudDayValues] = [:]
        let allDays = Set(strainByDay.keys).union(recoveryByDay.keys).union(sleepByDay.keys)
        for day in allDays {
            let rec = recoveryByDay[day]
            // WHOOP's hrv_rmssd_milli is in milliseconds already, matching Baseline's avgHrv unit.
            result[day] = CloudDayValues(
                restingHr: rec?.rhr, hrv: rec?.hrv, recovery: rec?.recovery,
                strain: strainByDay[day], sleepPerformance: sleepByDay[day])
        }
        return result
    }

    private static func persistReport(_ report: WhoopCloudComparisonReport) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: K.lastRunAt)
        UserDefaults.standard.set(report.summaryLines, forKey: K.lastReportSummary)
    }

    /// Resolved lazily to avoid a hard dependency from this file on app-level singletons; the app
    /// entry point wires these closures once at launch (see `register(deviceIdProvider:storeProvider:)`).
    private static var deviceIdProvider: (() -> String?)?
    private static var storeProvider: (() async -> WhoopStore?)?

    private static func currentDeviceRegistryId() -> String? {
        deviceIdProvider?()
    }

    private static func currentStore() async -> WhoopStore? {
        await storeProvider?()
    }

    /// Call once at app launch: registers the iOS BGTask handler AND supplies the closures the
    /// background/scheduled path needs to find the active device id and metrics store.
    public static func register(deviceIdProvider: @escaping () -> String?, storeProvider: @escaping () async -> WhoopStore?) {
        self.deviceIdProvider = deviceIdProvider
        self.storeProvider = storeProvider
        #if os(iOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                await catchUpIfDue()
                submitBackgroundRequest()
                task.setTaskCompleted(success: true)
            }
        }
        #endif
    }

    #if os(iOS)
    private static func submitBackgroundRequest() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(60, secondsUntilNextRun()))
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif
}
