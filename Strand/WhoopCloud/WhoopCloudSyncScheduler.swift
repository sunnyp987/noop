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
        // gap (app closed for weeks, a missed background run) would otherwise silently skip real
        // history that's available on both sides. `minDays` is the floor (a small overlap so a
        // slightly-late scheduled run still re-covers its own last window). A first-ever sync (no
        // `lastRunAt` yet) passes `nil` — per WHOOP's docs, omitting `start` returns EVERY record on
        // file, not a guessed-at cutoff — so day one backfills whatever history actually exists.
        let minDays = interval.days == 1 ? 3 : 10
        let days: Int?
        if let last = lastRunAt {
            let elapsedDays = Int(Date().timeIntervalSince(last) / 86_400) + 2
            days = max(minDays, elapsedDays)
        } else {
            days = nil
        }

        async let cycles = WhoopCloudAPI.recentCycles(days: days)
        async let recoveries = WhoopCloudAPI.recentRecoveries(days: days)
        async let sleeps = WhoopCloudAPI.recentSleep(days: days)
        let (cloudCycles, cloudRecoveries, cloudSleeps) = try await (cycles, recoveries, sleeps)

        // Write into Baseline's REAL store under the same imported source id the manual WHOOP CSV
        // export uses (Repository.whoopSource, "my-whoop"), so cloud-synced days show up in
        // Today/Trends/Sleep like an import always has, and a manual backfill + this ongoing sync
        // merge into one continuous history (imported source wins per day over the "-noop" computed
        // rows at read time, same as the CSV path). This can only ever persist WHOOP's OWN
        // already-computed numbers: Baseline's own algorithm needs the raw continuous BLE stream,
        // which the cloud API never exposes, so an imported day is never "what Baseline's algorithm
        // would have said" for that day — only WHOOP's.
        await writeIntoRealStore(store: store, cycles: cloudCycles, recoveries: cloudRecoveries, sleeps: cloudSleeps)

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

    // WHOOP's v2 timestamps carry fractional seconds (e.g. "2026-07-28T00:29:59.000Z"), which the
    // default ISO8601DateFormatter options silently fail to parse, so BOTH variants are tried.
    // Baseline's own DailyMetric.day is keyed by the DEVICE'S LOCAL calendar day (Repository.swift's
    // `dayKeyFormatter` never sets `timeZone`, so it defaults to TimeZone.current) — forcing UTC
    // here meant every night rolled to a different calendar date than Baseline's own row for
    // anyone not literally in UTC, so days almost never matched even when both sides had real data
    // for the same night. Match Baseline's convention: local time zone, no override. Shared by the
    // diagnostic comparison (`mergeCloudDays`) and the real-store writer (`writeIntoRealStore`) so
    // both agree on exactly which calendar day owns a given cloud record.
    private static func cloudDayKey(_ iso: String) -> String? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        guard let date = withFractional.date(from: iso) ?? whole.date(from: iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Per-day accumulator for the real-store write: `DailyMetric`'s fields are all `let`, so values
    /// are gathered here (cycle/recovery fields keyed by the cycle's start day, sleep fields keyed by
    /// the sleep's wake day — same day-ownership split `mergeCloudDays` already uses) and the
    /// immutable `DailyMetric` rows are built once, at the end.
    private struct DayAccum {
        var totalSleepMin: Double? = nil
        var efficiency: Double? = nil
        var deepMin: Double? = nil
        var remMin: Double? = nil
        var lightMin: Double? = nil
        var disturbances: Int? = nil
        var restingHr: Int? = nil
        var avgHrv: Double? = nil
        var recovery: Double? = nil
        var strain: Double? = nil
        var spo2Pct: Double? = nil
        var skinTempDevC: Double? = nil
        var respRateBpm: Double? = nil
        var activeKcalEst: Double? = nil
    }

    /// Maps WHOOP Cloud API records into the same `DailyMetric`/`MetricPoint` tables the manual CSV
    /// importer writes (`WhoopImporter.swift`), under the same imported source id, so cloud-synced
    /// history is indistinguishable from an import to every other screen in the app.
    private static func writeIntoRealStore(store: WhoopStore, cycles: [WhoopCloud.Cycle],
                                           recoveries: [WhoopCloud.Recovery], sleeps: [WhoopCloud.SleepActivity]) async {
        var accum: [String: DayAccum] = [:]
        var points: [MetricPoint] = []
        func addPoint(_ day: String, _ key: String, _ v: Double?) {
            if let v { points.append(MetricPoint(day: day, key: key, value: v)) }
        }

        var recoveryByCycleId: [Int: WhoopCloud.Recovery] = [:]
        for r in recoveries where r.scoreState == "SCORED" { recoveryByCycleId[r.cycleId] = r }

        for c in cycles {
            guard c.scoreState == "SCORED", let day = cloudDayKey(c.start) else { continue }
            var a = accum[day] ?? DayAccum()
            let rec = recoveryByCycleId[c.id]?.score
            a.strain = c.score?.strain
            // WHOOP reports cycle energy in kilojoules; Baseline's activeKcalEst is kcal (1 kcal = 4.184 kJ).
            a.activeKcalEst = c.score?.kilojoule.map { $0 / 4.184 }
            if let rec {
                a.restingHr = rec.restingHeartRate.map { Int($0.rounded()) }
                a.avgHrv = rec.hrvRmssdMilli
                a.recovery = rec.recoveryScore
                a.spo2Pct = rec.spo2Percentage
                // NOTE: WHOOP's cloud skin_temp_celsius is an absolute reading, not a baseline
                // deviation — same caveat as the CSV importer's skinTempDevC mapping.
                a.skinTempDevC = rec.skinTempCelsius
            }
            accum[day] = a

            addPoint(day, "strain", c.score?.strain)
            addPoint(day, "avg_hr", c.score?.averageHeartRate.map(Double.init))
            addPoint(day, "max_hr", c.score?.maxHeartRate.map(Double.init))
            addPoint(day, "energy_kcal", a.activeKcalEst)
            addPoint(day, "recovery", rec?.recoveryScore)
            addPoint(day, "rhr", rec?.restingHeartRate)
            addPoint(day, "hrv", rec?.hrvRmssdMilli)
            addPoint(day, "spo2", rec?.spo2Percentage)
            addPoint(day, "skin_temp", rec?.skinTempCelsius)
        }

        for s in sleeps where !s.nap {
            guard s.scoreState == "SCORED", let day = cloudDayKey(s.end), let score = s.score else { continue }
            var a = accum[day] ?? DayAccum()
            let stage = score.stageSummary
            let deepMin = stage?.totalSlowWaveSleepTimeMilli.map { $0 / 60_000 }
            let remMin = stage?.totalRemSleepTimeMilli.map { $0 / 60_000 }
            let lightMin = stage?.totalLightSleepTimeMilli.map { $0 / 60_000 }
            let awakeMin = stage?.totalAwakeTimeMilli.map { $0 / 60_000 }
            let totalSleepMin = [deepMin, remMin, lightMin].compactMap { $0 }.reduce(0, +)

            a.totalSleepMin = totalSleepMin > 0 ? totalSleepMin : a.totalSleepMin
            a.efficiency = score.sleepEfficiencyPercentage ?? a.efficiency
            a.deepMin = deepMin ?? a.deepMin
            a.remMin = remMin ?? a.remMin
            a.lightMin = lightMin ?? a.lightMin
            a.disturbances = stage?.disturbanceCount ?? a.disturbances
            a.respRateBpm = score.respiratoryRate ?? a.respRateBpm
            accum[day] = a

            addPoint(day, "sleep_total_min", totalSleepMin > 0 ? totalSleepMin : nil)
            addPoint(day, "sleep_deep_min", deepMin); addPoint(day, "sleep_rem_min", remMin)
            addPoint(day, "sleep_light_min", lightMin); addPoint(day, "awake_min", awakeMin)
            if let inBed = stage?.totalInBedTimeMilli { addPoint(day, "in_bed_min", inBed / 60_000) }
            addPoint(day, "resp_rate", score.respiratoryRate)
            addPoint(day, "sleep_efficiency", score.sleepEfficiencyPercentage)
            addPoint(day, "sleep_performance", score.sleepPerformancePercentage)
            addPoint(day, "sleep_consistency", score.sleepConsistencyPercentage)
            if let need = score.sleepNeeded {
                let needMin = ((need.baselineMilli ?? 0) + (need.needFromSleepDebtMilli ?? 0)
                    + (need.needFromRecentStrainMilli ?? 0) + (need.needFromRecentNapMilli ?? 0)) / 60_000
                if needMin > 0 {
                    addPoint(day, "sleep_need_min", needMin)
                    if totalSleepMin > 0 { addPoint(day, "hours_vs_needed_pct", totalSleepMin / needMin * 100) }
                }
            }
            if let deep = deepMin, let rem = remMin {
                addPoint(day, "restorative_min", deep + rem)
                if totalSleepMin > 0 { addPoint(day, "restorative_pct", (deep + rem) / totalSleepMin * 100) }
            }
        }

        guard !accum.isEmpty else { return }
        var metrics: [DailyMetric] = []
        for (day, a) in accum {
            metrics.append(DailyMetric(day: day, totalSleepMin: a.totalSleepMin, efficiency: a.efficiency, deepMin: a.deepMin,
                                        remMin: a.remMin, lightMin: a.lightMin, disturbances: a.disturbances, restingHr: a.restingHr,
                                        avgHrv: a.avgHrv, recovery: a.recovery, strain: a.strain, exerciseCount: nil,
                                        spo2Pct: a.spo2Pct, skinTempDevC: a.skinTempDevC, respRateBpm: a.respRateBpm,
                                        steps: nil, activeKcalEst: a.activeKcalEst))
        }
        let importedId = Repository.whoopSource
        _ = try? await store.upsertDailyMetrics(metrics, deviceId: importedId)
        try? await store.upsertMetricSeries(points, deviceId: importedId)
    }

    private static func mergeCloudDays(cycles: [WhoopCloud.Cycle], recoveries: [WhoopCloud.Recovery],
                                       sleeps: [WhoopCloud.SleepActivity]) -> [String: CloudDayValues] {
        var strainByDay: [String: Double] = [:]
        for c in cycles {
            guard let day = cloudDayKey(c.start), c.scoreState == "SCORED", let strain = c.score?.strain else { continue }
            strainByDay[day] = strain
        }

        var recoveryByDay: [String: (recovery: Double?, hrv: Double?, rhr: Double?)] = [:]
        let cycleStartById = Dictionary(uniqueKeysWithValues: cycles.map { ($0.id, $0.start) })
        for r in recoveries {
            guard r.scoreState == "SCORED", let start = cycleStartById[r.cycleId], let day = cloudDayKey(start) else { continue }
            recoveryByDay[day] = (r.score?.recoveryScore, r.score?.hrvRmssdMilli, r.score?.restingHeartRate)
        }

        var sleepByDay: [String: Double] = [:]
        for s in sleeps where !s.nap {
            guard let day = cloudDayKey(s.end), s.scoreState == "SCORED",
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
