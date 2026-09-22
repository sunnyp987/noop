import SwiftUI
import Charts
import StrandDesign
import StrandAnalytics
import StrandImport
import WhoopStore

/// Baseline — Health Monitor.
/// Live heart rate hero (ChartCard with a streaming sparkline + HR-zone footer),
/// then a uniform LazyVGrid of the body's vital signs (respiratory rate, blood
/// oxygen, resting HR, HRV, skin temp) as fixed-height StatTiles, each tinted and
/// captioned with its in-range state. Re-skinned to the locked Baseline component
/// system: every surface is a NoopCard, every metric is a StatTile, every chart is
/// a ChartCard — no ad-hoc card heights or paddings.
struct HealthView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    // NOTE: HealthView itself deliberately does NOT observe `LiveState`/`AppModel` for live HR. A
    // connected strap publishes at ~1 Hz; observing here would re-evaluate this body (and re-diff the
    // heavy vitals/skin-temp/age sections) on every tick. The ONLY live-dependent decision the parent
    // used to make — "empty state vs the live stack while there's no history yet" — now lives in the
    // `HealthFirstRunContent` leaf, which owns `live`/`model` itself. The common path (history present)
    // branches purely on `repo.days`, so a live tick re-renders only the `HeartRateSection` hero leaf.

    // MARK: - Body

    var body: some View {
        ScreenScaffold(title: "Health Monitor",
                       subtitle: "Live vitals, streamed from the strap.",
                       // PERF (scroll): lazy column — byte-identical layout (LazyVStack == eager VStack
                       // alignment/spacing/header); builds the trailing vitals/skin-temp/age sections on
                       // demand instead of all up-front.
                       onRefresh: { await repo.refresh() },
                       lazy: true,
                       // The day-of-sky liquid backdrop, matching Today / Sleep / Trends: a fixed,
                       // full-bleed time-of-day sky behind the scroll content (does not scroll).
                       topBackground: liquidScaffoldSky()) {
            if repo.days.isEmpty {
                // First run / no history: whether to show the empty state or the full live stack depends
                // on whether a strap is streaming live HR — a `live`-dependent choice. It's isolated to
                // this leaf (which owns `live`/`model`) so a ~1 Hz HR tick re-renders only this branch,
                // never the parent, and only while there's no history (a transient first-run state).
                HealthFirstRunContent()
            } else {
                // History present: `live` is irrelevant to the layout choice, so the parent renders the
                // full section stack directly without observing the HR stream.
                HealthSectionsStack()
            }
        }
    }
}

// MARK: - Content stacks

/// The full Health section stack (live HR hero + the static vitals/age/skin-temp sections). Each section
/// is its own leaf owning exactly what it needs, so only the `HeartRateSection` hero re-renders on a ~1 Hz
/// HR tick — the static sections depend on `repo`/`profile`/`model` snapshots only. Shared by the
/// history-present path and the first-run live path so the stack is defined once.
private struct HealthSectionsStack: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            // Manual "Sync now" + honest sync status (#364). Its own view so the ~1Hz HR stream
            // doesn't re-render it; depends on `live` (connection/backfill state) + `model`.
            SyncStatusSection()
            // The live HR section is its own view: it owns `live`/`profile`,
            // so the ~1Hz HR stream re-renders only this subtree — the static
            // vitals grid below does not re-render on each HR tick.
            HeartRateSection()
            // The three NEWEST age methodologies sit right after the HR hero — one screen's worth of
            // scroll, not eight — since these are the sections people ask about and can't find. The
            // weekly rolling-window family (the OLDER Fitness Age/Vitality cards) moves below them.
            HealthGroupDivider("NEW · BASELINE AGE, FULL-HISTORY, AND PHENOAGE")
            // Baseline Age: the original in-house multi-domain composite (cardio + HRV + sleep +
            // training load + respiratory stability), transparently combined — Baseline's own answer to
            // WHOOP's undisclosed Healthspan number, with every contributing domain visible.
            BaselineAgeSection()
            // A seam: Lifetime Averages is a DIFFERENT window on the SAME Nes/HUNT formula the weekly
            // Fitness Age/Vitality cards below use — your entire imported history in one pass, not a
            // rolling 7 days. This is the "full data age" (never blended with the weekly headline).
            HealthGroupDivider("FULL HISTORY BELOW · SAME FORMULA AS THIS WEEK'S")
            // Lifetime Fitness Age / Vitality: the SAME engines run over your ENTIRE imported history in
            // one pass, instead of the rolling 7-day window the weekly cards below use. A separate,
            // clearly labeled category so "what does using ALL my data say" is answerable without it
            // silently overriding "what does THIS WEEK say".
            LifetimeSnapshotSection()
            // Another seam: PhenoAge is neither of the above — a THIRD, separately-published formula
            // that runs on a lab blood panel instead of wearable signals at all.
            HealthGroupDivider("FROM YOUR LAB PANEL · A PUBLISHED CLINICAL FORMULA")
            // PhenoAge (StrandAnalytics.PhenoAgeEngine): Levine et al. 2018's clinical-chemistry
            // biological-age formula, computed the moment a full CBC + metabolic panel + CRP lands in
            // the Lab Book (e.g. from a Superpower-style panel or the new document scan). A published,
            // externally-validated formula — never blended with Baseline Age's own composite above.
            PhenoAgeSection()
            // A fourth seam: everything below uses the OLDER rolling 7-day window (the original Fitness
            // Age/Vitality cards) — kept for continuity, but no longer the first thing you see.
            HealthGroupDivider("THIS WEEK BELOW · ROLLING 7-DAY WINDOW")
            // Fitness Age (weekly, computed by IntelligenceEngine and read back from the
            // "fitness_age" metricSeries). Its own view depending only on `repo`/`profile`,
            // so the live HR stream never re-renders it.
            FitnessAgeSection()
            // Vitality / Body Age (weekly, computed by IntelligenceEngine from the mortality-
            // hazard model). Its own view depending only on repo/profile.
            VitalitySection()
            // Training Load Balance (weekly Acute:Chronic Workload Ratio, StrandAnalytics
            // TrainingLoadEngine). Shown here UNCONDITIONALLY (not gated behind the opt-in "Your
            // cards" customiser) so a genuinely new metric isn't buried behind a discovery step —
            // the same reasoning that put Fitness Age/Vitality here rather than only on the
            // customisable dashboard. Its own view depending only on repo.
            TrainingLoadSection()
            // Screen-5 recovery detail: the CONTRIBUTORS to today's recovery as
            // labelled progress bars (HRV / Resting HR / Sleep / Respiratory), each
            // scored against the on-device baseline. Depends only on `repo`.
            RecoveryContributorsSection()
            // The static vitals grid is its own view depending only on `repo`,
            // so it is unaffected by live HR ticks.
            VitalsSection()
            // v5 skin-temperature suite: the illness "heads-up", body clock, and (opt-in) cycle
            // awareness, each driven by a pure StrandAnalytics engine result the analytics pass
            // computed and AppModel publishes. Its own view depending on `model` + `repo`.
            SkinTempSection()
            // v5 deep-links: the records logbook + the multi-device fused record, reachable
            // from their honest Health home as drill-in rows (not their own destinations).
            HealthHubLinksSection()
        }
    }
}

/// First-run content (no history yet). Owns `live`/`model` so the live-HR-gated choice between the empty
/// state and the full live stack ticks here, in isolation, instead of re-rendering HealthView. Renders
/// byte-for-byte what the parent's inline `repo.days.isEmpty && !hasLiveHR` branch did.
private struct HealthFirstRunContent: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var model: AppModel

    /// HR to display: the spike-filtered median (model.bpm, #39) when available, else the reported
    /// value, else R-R-derived (the strap streams R-R even when its HR field reads 0).
    private var displayHR: Int? {
        if let hr = model.bpm, hr > 0 { return hr }
        if let hr = live.heartRate, hr > 0 { return hr }
        if let last = live.rr.last, last > 0 { return Int((60_000.0 / Double(last)).rounded()) }
        return nil
    }
    private var hasLiveHR: Bool { displayHR != nil }

    var body: some View {
        if !hasLiveHR {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                // Even with no history yet, a freshly-connected strap can be told to sync now (#364) —
                // so the control is reachable before the screen has any data to show.
                SyncStatusSection()
                ComingSoon(what: "No biometrics yet. Import your WHOOP export (and Apple Health if you have it) in Data Sources to fill this in.")
            }
        } else {
            HealthSectionsStack()
        }
    }
}

// MARK: - Sync status + "Sync now" (#364)

/// Manual "Sync now" control + honest sync status, mirroring the Android Sync-now button. Its own view
/// depending only on `live` (connection + backfill state) and `model` (the BLE pass-through), so the
/// ~1Hz live HR stream never re-renders it. Honesty rules (CLAUDE.md): the button is disabled and the
/// copy explains itself when no strap is connected; while a sync runs it shows the in-progress pill +
/// the live chunk count (never a fabricated percent — total pending is unknowable from the protocol);
/// otherwise it shows when history last synced.
private struct SyncStatusSection: View {
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var model: AppModel

    /// The strap link is usable for a manual offload kick (matches BLEManager.syncNow's own gate).
    private var canSync: Bool { live.connected && live.bonded && !live.backfilling }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Sync", overline: "Strap history",
                          trailing: live.connected ? (live.bonded ? String(localized: "Connected") : String(localized: "Pairing…")) : String(localized: "Offline"))

            NoopCard(tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                    statusRow

                    // Route the manual offload kick through the unified Baseline button system so the
                    // label sits centred at controlHeight like every other primary control. Reaches
                    // the BLE engine's gated entry point directly (same idiom as SettingsView's
                    // `model.ble.enableWhoop5DeepData()`); BLEManager.syncNow() is the honest gate —
                    // a no-op when no strap is connected or a sync is already running.
                    NoopButton(live.backfilling ? "Syncing…" : "Sync now",
                               systemImage: "arrow.triangle.2.circlepath",
                               kind: .secondary, fullWidth: true) {
                        model.ble.syncNow()
                    }
                    .disabled(!canSync)
                    .accessibilityLabel("Sync now")
                    .accessibilityHint(canSync
                        ? "Pulls your strap's stored history immediately, without waiting for the next automatic sync."
                        : (live.backfilling ? "A sync is already in progress." : "Connect your strap first."))

                    Text(helperText)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// The status line above the button: an in-progress pill while syncing (with the live chunk count),
    /// else a last-synced read-out, else an honest "not connected".
    @ViewBuilder private var statusRow: some View {
        if live.backfilling {
            // Reuse the shared in-progress affordance so this matches every other "syncing history" surface.
            SyncingHistoryNote(chunks: live.syncChunksThisSession)
        } else if !live.connected {
            StatePill("No strap connected", tone: .neutral, showsDot: false)
        } else if let last = live.lastSyncedAt {
            HStack(spacing: 8) {
                StatePill("History synced", tone: .positive)
                Text(relativeAgo(last))
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        } else {
            StatePill(live.bonded ? "Ready to sync" : "Pairing…",
                      tone: .accent, showsDot: true, pulsing: !live.bonded)
        }
    }

    private var helperText: String {
        if live.backfilling {
            return String(localized: "Pulling your strap's stored history. This drains oldest-first; a deep backlog now continues automatically across passes instead of waiting between syncs.")
        }
        if !live.connected {
            return String(localized: "Connect your strap to sync its stored history. Until then, only imported data shows here.")
        }
        if !live.bonded {
            return String(localized: "Finishing the pairing handshake. Sync now becomes available once the strap is paired.")
        }
        return String(localized: "Syncs your strap's stored history right away, instead of waiting for the next automatic sync.")
    }
}

// MARK: - Heart rate hero (live)

/// Live HR hero, split into its own view so the ~1Hz HR stream only re-renders this
/// subtree — the static vitals grid does not. Depends on `live` and `profile` only.
private struct HeartRateSection: View {
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var profile: ProfileStore
    @EnvironmentObject var model: AppModel

    /// Rolling buffer of recently-streamed live HR (newest last), so the hero graph builds a real
    /// continuous time-series instead of collapsing to a 2-point flat line when the strap streams HR
    /// but little/no R-R (the #105 case — Live HR works, but the Health graph showed only 2 samples).
    /// Each sample now carries the wall-clock time it arrived so the hero renders a real time x-axis
    /// (#198 — the chart had no time axis, so an iPhone user with no hover had no time context).
    /// Sampled on a fixed 1 Hz clock (#941), so the 180-sample cap is a strict rolling 3 minutes;
    /// resets when the view is recreated, which is fine for a live trace.
    @State private var hrHistory: [LiveHRSample] = []

    /// The 1 Hz sampling clock for the hero trace (#941, reimplemented from ryanbr's PR). The buffer
    /// used to append only when `displayHR` CHANGED, but AppModel deliberately republishes `bpm` only
    /// when the smoothed median actually moves, so a steady heart rate banked ZERO points and the
    /// time-axis chart drew one long phantom ramp from the last change to the next. Banking the current
    /// median once a second draws steady HR flat. Same let-property pattern as HRVSnapshotView's
    /// `secondTimer` (parent re-init resetting the tick phase is a non-issue here: this section is
    /// isolated and observes via @EnvironmentObject, per the perf note above).
    private let sampleTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    /// HR to display: the spike-filtered median (model.bpm, #39) when available — raw live.heartRate
    /// carries PPG harmonic spikes (real ~92 read as 170+); AppModel.bpm's doc mandates "every screen
    /// should show THIS". Falls back to the reported value, then R-R-derived, only until the median has a sample.
    private var displayHR: Int? {
        if let hr = model.bpm, hr > 0 { return hr }
        if let hr = live.heartRate, hr > 0 { return hr }
        if let last = live.rr.last, last > 0 { return Int((60_000.0 / Double(last)).rounded()) }
        return nil
    }
    private var hrIsDerived: Bool { (live.heartRate ?? 0) <= 0 && !live.rr.isEmpty }

    /// HR as a fraction of HR-max (0…1).
    private func hrFraction(_ hr: Int?) -> Double {
        guard let hr = hr, profile.hrMax > 0 else { return 0 }
        return min(max(Double(hr) / Double(profile.hrMax), 0), 1)
    }

    /// Current zone 1…5 from %HR-max (WHOOP/Karvonen-style bands: 50/60/70/80/90).
    private func hrZone(_ fraction: Double) -> Int {
        switch fraction {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default:      return 5
        }
    }

    /// A short, time-stamped HR series for the hero chart (newest last).
    /// Prefers the accumulated live-HR time-series — that's what a "live" graph should show, and it
    /// keeps growing even when the strap streams HR but sparse R-R (#105). Falls back to R-R-derived
    /// beats, then a flat line at the current HR. The R-R / flat fallbacks have no real per-sample
    /// timestamps, so we synthesise a 1 Hz trailing window ending "now" — the x-axis still reads as
    /// clock time and scrolls, matching the live buffer's behaviour (#198).
    private func hrSeries(_ hr: Int?) -> [LiveHRSample] {
        if hrHistory.count > 1 { return hrHistory }
        let beats = live.rr.suffix(60).compactMap { rr -> Double? in
            rr > 0 ? 60_000.0 / Double(rr) : nil
        }
        if beats.count > 1 { return Self.synthesiseSeries(beats) }
        if let hr = hr { return Self.synthesiseSeries([Double(hr), Double(hr)]) }
        return []
    }

    /// Wrap a bare value series in trailing 1 Hz timestamps ending at `Date()`, so the
    /// fallbacks (R-R-derived beats, flat line) chart on the same time x-axis as the live buffer.
    private static func synthesiseSeries(_ values: [Double]) -> [LiveHRSample] {
        let now = Date()
        let n = values.count
        return values.enumerated().map { i, v in
            LiveHRSample(date: now.addingTimeInterval(Double(i - (n - 1))), bpm: v)
        }
    }

    var body: some View {
        // Compute the derived live values ONCE per body pass and thread them into the
        // subviews, instead of re-evaluating heavy computed properties multiple times.
        let displayHR = self.displayHR
        let hasLiveHR = displayHR != nil
        let fraction = hrFraction(displayHR)
        let zone = hrZone(fraction)
        let series = hrSeries(displayHR)

        return VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Heart Rate", overline: "Live", trailing: hrIsDerived ? String(localized: "from R-R") : nil)

            // The live HR hero is a flat WHOOP card tinted rose — heart-rate's metric accent.
            // No scenic starfield / bloom: fill contrast carries the edge (Apple-flat).
            ChartCard(
                title: "Heart Rate",
                subtitle: hrIsDerived ? String(localized: "Estimated from R-R interval")
                    : (hasLiveHR ? String(localized: "Streaming live") : String(localized: "Awaiting strap")),
                trailing: hasLiveHR ? "\(displayHR!) bpm" : "—",
                tint: StrandPalette.metricRose
            ) {
                heroChart(displayHR: displayHR, hasLiveHR: hasLiveHR,
                          fraction: fraction, zone: zone, series: series)
            } footer: {
                ChartFooter([
                    ("Zone", hasLiveHR ? "Z\(zone)" : "—"),
                    ("% Max", hasLiveHR ? "\(Int((fraction * 100).rounded()))%" : "—"),
                    ("Max HR", "\(profile.hrMax)"),
                    ("State", hasLiveHR ? String(localized: "STREAMING") : String(localized: "IDLE")),
                ])
            }
        }
        .onReceive(sampleTimer) { now in
            // Bank the CURRENT spike-filtered HR once a second, stamped with the tick's real wall-clock
            // time: this feeds the time x-axis (#198) and the #105 trace without the phantom ramp that
            // on-change sampling drew through steady stretches (#941). The 30...220 physiological guard
            // mirrors the Android chart's existing range check; nil banks nothing (disconnect clears the
            // median on both platforms), so a stale value never flat-lines a dead trace.
            guard let v = displayHR, (30...220).contains(v) else { return }
            hrHistory.append(LiveHRSample(date: now, bpm: Double(v)))
            if hrHistory.count > 180 { hrHistory.removeFirst(hrHistory.count - 180) }
        }
    }

    /// The hero chart body: a tall, time-aware HR line tinted to the current zone, with a
    /// status pill floated top-trailing. Fixed to NoopMetrics.chartHeight via ChartCard.
    private func heroChart(displayHR: Int?, hasLiveHR: Bool,
                           fraction: Double, zone: Int, series: [LiveHRSample]) -> some View {
        ZStack(alignment: .topTrailing) {
            if series.count > 1 {
                LiveTimeChart(
                    samples: series,
                    gradient: Gradient(colors: [
                        StrandPalette.hrZoneColor(max(1, zone - 1)),
                        StrandPalette.hrZoneColor(zone),
                    ])
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Live heart rate over time")
                .accessibilityValue(hasLiveHR ? "\(displayHR ?? 0) beats per minute, zone \(zone)" : "no data")
            } else {
                VStack(spacing: NoopMetrics.space2) {
                    // The big fallback numeral ticks up to the live value (the hero number) — under
                    // Reduce Motion it snaps. When there's no HR yet we show a crisp em-dash instead.
                    if let hr = displayHR {
                        CountUpText(value: Double(hr),
                                    format: { "\(Int($0.rounded()))" },
                                    font: StrandFont.display(72),
                                    color: hasLiveHR ? StrandPalette.hrZoneColor(zone) : StrandPalette.textTertiary)
                            .tracking(StrandFont.displayTracking(72))
                    } else {
                        Text("—")
                            .font(StrandFont.display(72))
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    Text("bpm").font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            StatePill("\(zoneLabel(hasLiveHR: hasLiveHR, zone: zone, fraction: fraction))",
                      tone: hasLiveHR ? .accent : .neutral,
                      showsDot: hasLiveHR,
                      pulsing: hasLiveHR)
        }
    }

    private func zoneLabel(hasLiveHR: Bool, zone: Int, fraction: Double) -> String {
        guard hasLiveHR else { return String(localized: "Idle") }
        return String(localized: "Zone \(zone) · \(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - Live HR sample + time chart

/// One streamed live-HR reading with the wall-clock time it arrived. Carrying the time
/// (rather than a bare bpm) is what lets the hero render a real time x-axis (#198).
struct LiveHRSample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let bpm: Double
}

/// The live HR hero chart: a zone-gradient line + soft area over a real **time** x-axis
/// (hour:minute:second), so the trace visibly scrolls as new samples arrive. Replaces the
/// axis-less Sparkline on this hero (#198) — an iPhone user has no hover, so the visible
/// clock axis is the fix. Built on Swift Charts; the strict rolling 3-minute window comes
/// from the caller's 1 Hz-sampled, 180-capped buffer (HeartRateSection.hrHistory, #941).
private struct LiveTimeChart: View {
    var samples: [LiveHRSample]
    /// The gradient the line/area is stroked with (the current HR-zone band).
    var gradient: Gradient

    /// Auto-fitted y bounds with a little headroom so the trace never kisses the edges.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map(\.bpm)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi { return (lo - 5)...(hi + 5) }
        let pad = (hi - lo) * 0.12
        return (lo - pad)...(hi + pad)
    }

    /// A vertical gradient keyed bottom→top so the stroke colour tracks the zone band.
    private var lineGradient: LinearGradient {
        LinearGradient(gradient: gradient, startPoint: .bottom, endPoint: .top)
    }

    /// The lightest stop of the zone gradient, used to tint the area wash.
    private var areaTint: Color {
        StrandPalette.sample(stops: gradient.stops, at: 0.85)
    }

    var body: some View {
        Chart(samples) { s in
            AreaMark(
                x: .value("Time", s.date),
                y: .value("BPM", s.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [areaTint.opacity(0.24), Color.clear],
                    startPoint: .top, endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", s.date),
                y: .value("BPM", s.bpm)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .foregroundStyle(lineGradient)
        }
        .chartYScale(domain: yDomain)
        // catmullRom overshoots on sharp HR turns and the area fill draws unclipped — clip the
        // plot so nothing bleeds below the card (mirrors TrendChart's fix for #104).
        .chartPlotStyle { plotArea in plotArea.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(0.4))
                AxisValueLabel(format: .dateTime.hour().minute().second())
                    .foregroundStyle(StrandPalette.textTertiary)
                    .font(StrandFont.footnote)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(StrandPalette.hairline.opacity(0.4))
                AxisValueLabel().foregroundStyle(StrandPalette.textTertiary)
                    .font(StrandFont.footnote)
            }
        }
        .clipped()
    }
}

// MARK: - Recovery contributors (screen-5: labelled progress bars)

/// The README "Recovery detail · CONTRIBUTORS" section: the inputs to today's recovery
/// (HRV, Resting HR, Sleep, Respiratory) as labelled zone/stage progress bars, each scored
/// 0–100 against the user's on-device baseline. Depends only on `repo`, so the ~1Hz live HR
/// stream never re-renders it. Presentation-only — every value reads off the latest
/// `DailyMetric` and the baseline mean of prior nights; nothing here changes data or scoring.
private struct RecoveryContributorsSection: View {
    @EnvironmentObject var repo: Repository

    /// One contributor row's resolved read-out: its 0–100 strength, the qualitative word,
    /// the metric hue, and the right-aligned raw value.
    private struct Contributor {
        let label: LocalizedStringKey
        let strength: Double?      // 0…100, nil while calibrating / no value
        let word: String
        let detail: String         // right-aligned raw reading ("64 ms")
        let tint: Color
    }

    var body: some View {
        let latest = repo.days.last
        // A contributor needs at least the recovery seed depth of prior nights to score against
        // a baseline; below that we show CALIBRATING and leave the bars unfilled but honest.
        let priorCount = repo.days.dropLast().compactMap(\.avgHrv).filter { $0 > 0 }.count
        let ready = priorCount >= Baselines.minNightsSeed
        let contributors = buildContributors(latest)

        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionHeader("Contributors", overline: "Recovery", trailing: nil)
                if ready {
                    ScoreStatePill(.solid)
                } else {
                    ScoreStatePill(.calibrating, text: "Calibrating (\(priorCount) of \(Baselines.minNightsSeed))")
                }
            }
            NoopCard(tint: StrandPalette.chargeColor) {
                VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                    ForEach(Array(contributors.enumerated()), id: \.offset) { idx, c in
                        ContributorBar(label: c.label, strength: ready ? c.strength : nil,
                                       word: ready ? c.word : String(localized: "Calibrating"),
                                       detail: c.detail, tint: c.tint)
                            .staggeredAppear(index: idx)
                    }
                }
            }
            Text("Baselines are learned on-device over your first 14 days. Until then, typical ranges apply.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Resolve each contributor from the latest day against the baseline mean of prior nights.
    /// HRV and Sleep score higher when above baseline; Resting HR and Respiratory score higher
    /// when at/below baseline (lower is better). Strength is a centred 0–100 (baseline ≈ 70).
    private func buildContributors(_ latest: DailyMetric?) -> [Contributor] {
        let hrvBase  = baseline { $0.avgHrv }
        let rhrBase  = baseline { $0.restingHr.map(Double.init) }
        let sleepBase = baseline { $0.totalSleepMin }
        let respBase = baseline { $0.respRateBpm }

        return [
            Contributor(
                label: "HRV",
                strength: higherIsBetter(latest?.avgHrv, base: hrvBase),
                word: word(higherIsBetter(latest?.avgHrv, base: hrvBase)),
                detail: latest?.avgHrv.map { "\(Int($0.rounded())) ms" } ?? "—",
                tint: StrandPalette.metricCyan),       // HRV = teal
            Contributor(
                label: "Resting HR",
                strength: lowerIsBetter(latest?.restingHr.map(Double.init), base: rhrBase),
                word: word(lowerIsBetter(latest?.restingHr.map(Double.init), base: rhrBase)),
                detail: latest?.restingHr.map { "\($0) bpm" } ?? "—",
                tint: StrandPalette.chargeColor),       // recovery contributor = WHOOP green
            Contributor(
                label: "Sleep",
                strength: higherIsBetter(latest?.totalSleepMin, base: sleepBase),
                word: word(higherIsBetter(latest?.totalSleepMin, base: sleepBase)),
                detail: latest?.totalSleepMin.map { sleepText($0) } ?? "—",
                tint: StrandPalette.sleepLight),       // sleep = blue
            Contributor(
                label: "Respiratory",
                strength: lowerIsBetter(latest?.respRateBpm, base: respBase),
                word: word(lowerIsBetter(latest?.respRateBpm, base: respBase)),
                detail: latest?.respRateBpm.map { String(format: "%.1f rpm", $0) } ?? "—",
                tint: StrandPalette.sleepLight),       // respiratory shares the blue world
        ]
    }

    /// Mean of a per-day column across prior nights (excludes the latest day so "vs baseline"
    /// compares the latest reading against history). nil until enough nights exist.
    private func baseline(_ key: (DailyMetric) -> Double?) -> Double? {
        let prior = repo.days.dropLast().compactMap(key).filter { $0 > 0 }
        guard prior.count >= Baselines.minNightsSeed else { return nil }
        return prior.reduce(0, +) / Double(prior.count)
    }

    /// Centre a "higher is better" reading on a 0…100 strength: at baseline → 70, scaling up to
    /// 100 by ~+30% above and down to 0 by ~-40% below. nil inputs return nil (no bar fill).
    private func higherIsBetter(_ value: Double?, base: Double?) -> Double? {
        guard let value, let base, base > 0 else { return nil }
        let ratio = value / base
        return clampStrength(70 + (ratio - 1) * 100)
    }
    /// Centre a "lower is better" reading (RHR, respiratory) — at baseline → 70, better as it falls.
    private func lowerIsBetter(_ value: Double?, base: Double?) -> Double? {
        guard let value, let base, base > 0 else { return nil }
        let ratio = value / base
        return clampStrength(70 - (ratio - 1) * 200)
    }
    private func clampStrength(_ v: Double) -> Double { min(100, max(0, v)) }

    /// The qualitative word under the bar's right edge — banded like the contributor strengths.
    private func word(_ strength: Double?) -> String {
        guard let s = strength else { return "—" }
        switch s {
        case ..<40:  return String(localized: "Low")
        case ..<60:  return String(localized: "Fair")
        case ..<78:  return String(localized: "Good")
        default:     return String(localized: "Strong")
        }
    }

    private func sleepText(_ minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        return "\(m / 60)h \(m % 60)m"
    }
}

/// One README "zone / stage bar": a label + qualitative word on top, the signature liquid `LiquidTube`
/// (a metric-tinted horizontal tube that fills to the 0…100 strength, matching Today's Key-Metrics and
/// Last-Workouts tubes), and a right-aligned raw reading. Used for the recovery contributors. A nil
/// strength (calibrating) renders an empty tube — no fabricated fill.
private struct ContributorBar: View {
    let label: LocalizedStringKey
    /// 0…100 strength; nil renders an empty (calibrating) track.
    let strength: Double?
    let word: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).strandOverline()
                Text("· \(word)")
                    .font(StrandFont.footnote)
                    .foregroundStyle(strength == nil ? StrandPalette.textTertiary : tint)
                Spacer()
                Text(detail)
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            // The signature liquid tube: fills to the 0…1 strength, tinted to the contributor's world.
            // Static (posed) — a row of small bars shouldn't each run a live 30fps Canvas. Calibrating
            // (nil) reads as an empty 0 tube.
            LiquidTube(frac: (strength ?? 0) / 100, tint: tint, height: 10, animated: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(detail), \(word)")
    }
}

// MARK: - Fitness Age

/// The "Fitness Age" section: a weekly, on-device fitness comparison (NOT a biological age) computed by
/// IntelligenceEngine from the Nes/HUNT model and read back from the "fitness_age" metricSeries under the
/// strap source. Depends only on `repo` (the weekly value + the recent dailies that drive the readiness
/// checklist) and `profile` (age/sex/waist), so the ~1Hz live HR stream never re-renders it.
///
/// Two states, both honest about coverage:
///   • a value exists → a scenic hero "Fitness Age N" + a younger/older-than-your-age subtitle and a faint
///     ±band caption, tappable through to the metric's full trend, with an "ⓘ How accurate is this?"
///     affordance that reveals the readiness checklist.
///   • no value yet → the checklist card directly, with required-missing inputs deep-linking to Settings.
///
/// The checklist groups inputs by ROLE exactly as the engine reports them: "Drives your Fitness Age"
/// (age/sex/resting-HR/activity) vs "Unlocks your VO₂max" (height+weight/waist) — never implying the body
/// measurements sharpen the age (the body term cancels in the model).
private struct FitnessAgeSection: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore

    /// Latest weekly Fitness Age (years) read from the "fitness_age" metricSeries, nil until loaded/computed.
    @State private var fitnessAge: Double?
    /// Latest estimated VO₂max (ml/kg/min) from "vo2max_est" — only present once a waist is set.
    @State private var vo2max: Double?
    /// The "yyyy-MM-dd" week-anchor (Saturday) the shown number is FROM — may be weeks/months in the
    /// past for a backfilled week (see IntelligenceEngine.computeAndPersistWeeklyFitnessVitality). Shown
    /// so a comparison against another app's same-week number is apples-to-apples, not "today vs then".
    @State private var fitnessAgeWeekOf: String?
    @State private var loaded = false

    /// Reveal the readiness checklist (the "ⓘ How accurate is this?" disclosure under a shown value).
    @State private var showReadiness = false

    /// The two drill-downs this section can present, as ONE enum-driven sheet — two stacked
    /// `.sheet` modifiers race on macOS (only one wins) and neither carried a fixed frame, so a
    /// single item-driven sheet (mirrors WorkoutsView / FusedRecordView) is the reliable idiom.
    /// - `.trend`: the full metric trend (existing MetricDetailView for "fitness_age"). These shared
    ///   screens aren't hosted in a per-screen NavigationStack, so a sheet is the in-app drill-down.
    /// - `.settings`: Settings (the profile card) so a required-missing input can be filled in place.
    private enum FitnessSheet: String, Identifiable {
        case trend, settings
        var id: String { rawValue }
    }
    @State private var fitnessSheet: FitnessSheet?

    /// The catalog descriptor backing the trend sheet + accent.
    private var fitnessAgeMetric: MetricDescriptor? { MetricCatalog.all.first { $0.key == "fitness_age" } }

    /// "vs age N · week of Mon D" when the anchor week is known, so a comparison against another app's
    /// reading for the SAME week is apples-to-apples rather than "today" vs "whenever this last computed".
    private func weekOfTrailing(vsAge age: Int) -> String {
        guard let day = fitnessAgeWeekOf, let date = Repository.date(fromDay: day) else {
            return String(localized: "vs age \(age)")
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return String(localized: "vs age \(age) · week of \(fmt.string(from: date))")
    }

    /// Build the readiness verdict from the same signals IntelligenceEngine feeds the engine: the last 7
    /// computed/imported days give the resting-HR + activity coverage counts; the profile gives the rest.
    private var readiness: FitnessAgeReadiness {
        let last7 = repo.days.suffix(7)
        let rhrDays = last7.compactMap { $0.restingHr }.count
        let activityDays = last7.compactMap { $0.strain }.count
        return FitnessAgeEngine.assessReadiness(
            hasAge: profile.age > 0,
            hasSex: !profile.sex.isEmpty,
            rhrDays: rhrDays,
            activityDays: activityDays,
            hasHeightWeight: profile.heightCm > 0 && profile.weightKg > 0,
            hasWaist: profile.waistCm > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Fitness Age", overline: "This week",
                          trailing: fitnessAge != nil ? weekOfTrailing(vsAge: profile.age) : nil)
            content
        }
        .sheet(item: $fitnessSheet) { which in
            NavigationStack {
                switch which {
                case .trend:
                    if let m = fitnessAgeMetric { MetricDetailView(metric: m) }
                case .settings:
                    SettingsView()
                }
            }
            #if os(macOS)
            .frame(width: 900, height: 820)
            #endif
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let age = fitnessAge {
            heroCard(age: age)
            if showReadiness {
                ReadinessChecklistCard(readiness: readiness,
                                       lead: nil,
                                       onFix: { fitnessSheet = .settings })
                    .transition(.opacity)
            }
        } else if loaded {
            // No value yet: lead with the checklist so the user sees exactly what's still needed.
            ReadinessChecklistCard(
                readiness: readiness,
                lead: readiness.canCompute
                    ? "A few more days and we can show your Fitness Age."
                    : "A few more days of wear, plus the basics below, and we can show your Fitness Age.",
                onFix: { fitnessSheet = .settings })
        } else {
            // Brief read of the weekly value; honest placeholder rather than an empty gap.
            ComingSoon(what: "Reading your Fitness Age…", symbol: "figure.run")
        }
    }

    /// The hero vessel's fill (0…1): younger reads FULLER. Maps a fitness age across a 20…70-year span
    /// onto a full→empty gauge, so a 30-year fitness age fills high and a 65 fills low. Purely a visual
    /// anchor for the gauge — the number and the ± band carry the real read-out.
    private func fitnessAgeFraction(_ age: Double) -> Double {
        let lo = 20.0, hi = 70.0
        return max(0.05, min(1, (hi - age) / (hi - lo)))
    }

    /// The younger/older-than-your-age subtitle as whole-phrase variants per count and direction, so
    /// translators see complete sentences (never a stitched plural or direction fragment).
    private func ageDeltaLine(years: Int, younger: Bool) -> String {
        if years == 0 { return String(localized: "About the same as your age") }
        switch (younger, years == 1) {
        case (true, true):   return String(localized: "1 year younger than your age")
        case (true, false):  return String(localized: "\(years) years younger than your age")
        case (false, true):  return String(localized: "1 year older than your age")
        case (false, false): return String(localized: "\(years) years older than your age")
        }
    }

    /// The shown-value hero: a scenic Charge-world backdrop, the big Fitness Age number, a
    /// younger/older-than-your-age subtitle, the optional VO₂max, the ±band disclaimer, and the two
    /// affordances (tap-through to the trend + the "How accurate is this?" disclosure).
    private func heroCard(age: Double) -> some View {
        let shown = Int(age.rounded())
        let delta = Double(profile.age) - age        // +ve = fitness age younger than chronological
        let years = Int(abs(delta).rounded())
        let younger = delta >= 0
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            // Tap the hero body to open the full "fitness_age" trend.
            Button { fitnessSheet = .trend } label: {
                HStack(alignment: .center, spacing: NoopMetrics.space5) {
                    // The signature liquid gauge anchors the hero: a vessel tinted to the Charge world,
                    // filled by how young the fitness age reads (younger = fuller), with the age counting
                    // up over it. Same HeroScoreCell idiom as Today; taps fall through to the trend button.
                    ZStack {
                        LiquidVessel(value: fitnessAgeFraction(age), tint: StrandPalette.chargeColor, animated: true)
                            .frame(width: 96, height: 96)
                        CountUpNumber(value: Double(shown), font: StrandFont.rounded(30))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                            .allowsHitTesting(false)
                    }
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Fitness Age").strandOverline()
                        Text(ageDeltaLine(years: years, younger: younger))
                            .font(StrandFont.subhead)
                            .foregroundStyle(younger ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                    }
                    Spacer(minLength: 0)
                    if let vo2 = vo2max {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("VO₂max").strandOverline()
                            Text(String(format: "%.0f", vo2))
                                .font(StrandFont.number(30))
                                .foregroundStyle(StrandPalette.metricCyan)
                            Text("ml/kg/min")
                                .font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Fitness Age \(shown), \(ageDeltaLine(years: years, younger: younger)). Tap to see the trend.")

            Text("± \(Int(FitnessAgeEngine.displayBandYears)) yr · a fitness comparison, not a biological age")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)

            Divider().overlay(StrandPalette.hairline)

            // The honest disclosure: what we have / what we still need, grouped by what it unlocks.
            Button {
                withAnimation(StrandMotion.interactive) { showReadiness.toggle() }
            } label: {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    Text("How accurate is this?")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Spacer()
                    Image(systemName: showReadiness ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(LiquidPressStyle())
            // Whole-string key per variant (never a stitched Hide/Show fragment).
            .accessibilityLabel(showReadiness
                ? "How accurate is this? Hide the data behind your Fitness Age"
                : "How accurate is this? Show the data behind your Fitness Age")
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Apple-flat WHOOP card: a plain frosted surface tinted to the Charge (green) world —
        // no scenic starfield / bloom, no gold border. Fill contrast carries the edge.
        .background {
            FrostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    /// Load the latest weekly Fitness Age (+ optional VO₂max) from the strap's metricSeries. Uses the
    /// same `exploreSeries(key:source:)` path every other metric on this screen reads, with source
    /// "my-whoop" (the Repository merges the computed "-noop" rows under any real import). Takes the
    /// freshest point — the weekly value is keyed to the week's Saturday and refines through the week.
    private func load() async {
        let faPts = await repo.exploreSeries(key: "fitness_age", source: "my-whoop")
        let vo2Pts = await repo.exploreSeries(key: "vo2max_est", source: "my-whoop")
        fitnessAge = faPts.last?.value
        fitnessAgeWeekOf = faPts.last?.day
        vo2max = vo2Pts.last?.value
        loaded = true
    }
}

/// The readiness checklist card: an optional lead line, then the engine's `items` as ✓/⚠/○ rows with
/// their `detail` text, GROUPED by `.role` into "Drives your Fitness Age" and "Unlocks your VO₂max".
/// A required-but-missing input shows a "Fix in Settings" affordance (the engine's required+missing
/// rows are age/sex; resting-HR can only be earned by wearing the strap, so it gets no fix button).
private struct ReadinessChecklistCard: View {
    let readiness: FitnessAgeReadiness
    /// Optional intro line shown above the groups (e.g. the "a few more days" no-value message).
    let lead: LocalizedStringKey?
    /// Invoked when the user taps a required-missing row's "Fix in Settings".
    let onFix: () -> Void

    private var drivesAge: [FitnessReadinessItem] { readiness.items.filter { $0.role == .drivesAge } }
    private var unlocksVO2: [FitnessReadinessItem] { readiness.items.filter { $0.role == .unlocksVO2max } }

    var body: some View {
        NoopCard(tint: StrandPalette.chargeColor) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                HStack(spacing: NoopMetrics.rowSpacing) {
                    confidencePill
                    Spacer(minLength: 0)
                }
                if let lead {
                    Text(lead)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                group(title: "Drives your Fitness Age", items: drivesAge)
                group(title: "Unlocks your VO₂max", items: unlocksVO2)
                Text("Built from published methods (Nes/HUNT) on \(Platform.deviceNounPhrase). It's a fitness comparison against an average peer your age, not a biological or medical age.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The overall confidence chip, mapped onto the existing score-lifecycle pill vocabulary.
    @ViewBuilder private var confidencePill: some View {
        switch readiness.confidence {
        case .ready:    ScoreStatePill(.solid, text: "Ready")
        case .estimate: ScoreStatePill(.building, text: "Estimate (partial data)")
        case .notReady: ScoreStatePill(.calibrating, text: "Not enough data yet")
        }
    }

    @ViewBuilder
    private func group(title: LocalizedStringKey, items: [FitnessReadinessItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.rowSpacing) {
                Text(title).strandOverline()
                ForEach(items, id: \.key) { item in
                    readinessRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func readinessRow(_ item: FitnessReadinessItem) -> some View {
        // A required/optional input that's still unsatisfied earns a "Fix in Settings" affordance, but
        // only when it's actually fixable there (age/sex/body metrics/waist) — resting-HR and activity
        // coverage come from wearing the strap, so those get no fix button.
        let fixable = item.status != .satisfied
            && (item.key == "age" || item.key == "sex" || item.key == "bodyMetrics" || item.key == "waist")
        let row = HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: statusIcon(item.status))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusColor(item.status))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(item.detail)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 0)
            if fixable {
                Button(action: onFix) {
                    Text("Fix in Settings")
                        .font(StrandFont.footnote.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.label): \(item.detail). Fix in Settings.")
            }
        }
        // When a Fix button is present keep it as its own VoiceOver stop (.contain); otherwise fold the
        // whole row into one labelled stop. Two branches so we never pass a nil accessibility label.
        if fixable {
            row.accessibilityElement(children: .contain)
        } else {
            row
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.label), \(statusWord(item.status)). \(item.detail)")
        }
    }

    private func statusIcon(_ s: FitnessReadinessStatus) -> String {
        switch s {
        case .satisfied: return "checkmark.circle.fill"
        case .partial:   return "exclamationmark.triangle.fill"
        case .missing:   return "circle"
        }
    }
    private func statusColor(_ s: FitnessReadinessStatus) -> Color {
        switch s {
        case .satisfied: return StrandPalette.statusPositive
        case .partial:   return StrandPalette.statusWarning
        case .missing:   return StrandPalette.textTertiary
        }
    }
    private func statusWord(_ s: FitnessReadinessStatus) -> String {
        switch s {
        case .satisfied: return String(localized: "ready")
        case .partial:   return String(localized: "partial")
        case .missing:   return String(localized: "missing")
        }
    }
}

// MARK: - Vitality / Body Age

/// The "Vitality" section: a weekly wellness score (0–100) + a Body Age in years, computed by
/// IntelligenceEngine from the published mortality-hazard model and read back from the metricSeries.
/// A wellness trend from your habits — NOT a clinical biological age. Recomputes the live best/worst
/// factor the same way the engine does, for the plain-English "why".
private struct VitalitySection: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @State private var vitality: Double?
    @State private var bodyAge: Double?
    /// The "yyyy-MM-dd" week-anchor the shown Vitality/Body Age is FROM (see FitnessAgeSection's
    /// `fitnessAgeWeekOf` for why this matters for an apples-to-apples cross-app comparison).
    @State private var vitalityWeekOf: String?
    @State private var loaded = false

    private var contributions: [VitalityEngine.Contribution] {
        let last7 = repo.days.suffix(7)
        let nights = last7.compactMap { $0.totalSleepMin }.map { Double($0) / 60.0 }.filter { $0 > 0 }
        let hrvs = last7.compactMap { $0.avgHrv }
        let rhrs = last7.compactMap { $0.restingHr }.map(Double.init)
        let steps = last7.compactMap { $0.steps }.map(Double.init)
        func mean(_ a: [Double]) -> Double? { a.isEmpty ? nil : a.reduce(0, +) / Double(a.count) }
        // Aggregate EXACTLY as the stored headline does (IntelligenceEngine), so this "what's driving it"
        // breakdown reconciles with the Vitality / Body Age number it explains rather than being recomputed
        // on different statistics: resting HR + HRV are MEDIANED (robust to one outlier night), sleep +
        // steps are MEANED. Using the mean for all four let a single bad RHR/HRV reading drift the breakdown
        // out of step with the median-based headline (code review).
        return VitalityEngine.contributions(.init(
            chronoAge: Double(profile.age),
            restingHR: rhrs.isEmpty ? nil : IntelligenceEngine.medianOf(rhrs),
            sleepHours: mean(nights),
            sleepConsistency: VitalityEngine.sleepConsistency(nightlyHours: nights),
            rmssd: hrvs.isEmpty ? nil : IntelligenceEngine.medianOf(hrvs),
            rmssdNorm: VitalityEngine.rmssdNorm(forAge: Double(profile.age)),
            steps: mean(steps)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Vitality", overline: "This week", trailing: vitalityTrailing())
            if let v = vitality, let ba = bodyAge {
                hero(vitality: v, bodyAge: ba)
            } else if loaded {
                ComingSoon(what: "A few more days and we can show your Vitality.", symbol: "sparkles")
            } else {
                ComingSoon(what: "Reading your Vitality…", symbol: "sparkles")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    /// "Body Age N · week of Mon D" when known, so the reader can line up this reading against another
    /// app's number for the SAME week rather than assuming it's today's.
    private func vitalityTrailing() -> String? {
        guard let bodyAge else { return nil }
        let ageText = String(localized: "Body Age \(Int(bodyAge.rounded()))")
        guard let day = vitalityWeekOf, let date = Repository.date(fromDay: day) else { return ageText }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(ageText) · \(String(localized: "week of \(fmt.string(from: date))"))"
    }

    private func hero(vitality v: Double, bodyAge ba: Double) -> some View {
        let delta = Double(profile.age) - ba
        let younger = delta >= 0
        let yrs = Int(abs(delta).rounded())
        let sorted = contributions.sorted { $0.lnHazard < $1.lnHazard }
        let best = sorted.first
        let worst = sorted.last
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: NoopMetrics.space5) {
                // The weekly Vitality score (0…100) as the signature liquid gauge: a vessel tinted to the
                // Charge world, filled to the score, with the number counting up over it (Today's
                // HeroScoreCell idiom). Taps splash the gauge; the number is hit-transparent.
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Vitality").strandOverline()
                    ZStack {
                        LiquidVessel(value: max(0, min(1, v / 100)), tint: StrandPalette.chargeColor, animated: true)
                            .frame(width: 108, height: 108)
                        VStack(spacing: 0) {
                            CountUpNumber(value: v, font: StrandFont.rounded(38))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
                            Text("of 100").font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                        }
                        .allowsHitTesting(false)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Vitality \(Int(v.rounded())) out of 100")
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                    Text("Body Age").strandOverline()
                    CountUpText(value: ba,
                                format: { "\(Int($0.rounded()))" },
                                font: StrandFont.number(34),
                                color: StrandPalette.textPrimary)
                    Text(bodyAgeDeltaLine(yrs: yrs, younger: younger))
                        .font(StrandFont.footnote)
                        .foregroundStyle(younger ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                }
            }
            if (best?.lnHazard ?? 0) < 0 || (worst?.lnHazard ?? 0) > 0 {
                Divider().overlay(StrandPalette.hairline)
                if let best, best.lnHazard < 0 {
                    Text("Helping most: \(best.label)")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusPositive)
                }
                if let worst, worst.lnHazard > 0 {
                    Text("Holding you back: \(worst.label)")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
                }
            }
            Text("A wellness estimate from your habits, not a clinical biological age.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Apple-flat WHOOP card: a plain frosted surface tinted to the Charge (green) world —
        // no scenic starfield / bloom, no gold border. Fill contrast carries the edge.
        .background {
            FrostedCardSurface(tint: StrandPalette.chargeColor, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    /// The Body Age delta as whole-phrase variants per count and direction, so translators see
    /// complete phrases (never a stitched plural or direction fragment).
    private func bodyAgeDeltaLine(yrs: Int, younger: Bool) -> String {
        if yrs == 0 { return String(localized: "about your age") }
        switch (younger, yrs == 1) {
        case (true, true):   return String(localized: "1 yr younger")
        case (true, false):  return String(localized: "\(yrs) yrs younger")
        case (false, true):  return String(localized: "1 yr older")
        case (false, false): return String(localized: "\(yrs) yrs older")
        }
    }

    private func load() async {
        let vPts = await repo.exploreSeries(key: "vitality", source: "my-whoop")
        vitality = vPts.last?.value
        vitalityWeekOf = vPts.last?.day
        bodyAge = (await repo.exploreSeries(key: "body_age", source: "my-whoop")).last?.value
        loaded = true
    }
}

// MARK: - Baseline Age (original, in-house, multi-domain)

/// "Baseline Age": BiometricAgeEngine's own original composite — cardiorespiratory (RHR + activity),
/// autonomic (HRV vs an age-normative curve), sleep (duration + regularity), training-load balance, and
/// respiratory stability, combined with a smooth saturating curve instead of a single linear formula.
/// Distinct from "Fitness Age" above (which is the literal Nes/HUNT published equation) — this is
/// Baseline's own construction, transparently: every domain's years-contribution is shown, unlike WHOOP's
/// undisclosed Healthspan number.
private struct BaselineAgeSection: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @State private var trainingLoadRatio: Double?
    @State private var loaded = false

    private var result: BiometricAgeEngine.Result? {
        let last7 = repo.days.suffix(7)
        let rhrs = last7.compactMap { $0.restingHr }.map(Double.init)
        let activeStrains = last7.compactMap { $0.strain }.filter { $0 >= 30 }
        let meanActiveStrain = activeStrains.isEmpty ? 0 : activeStrains.reduce(0, +) / Double(activeStrains.count)
        let pai = FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: activeStrains.count, meanActiveStrain: meanActiveStrain)
        let nights = last7.compactMap { $0.totalSleepMin }.map { Double($0) / 60.0 }.filter { $0 > 0 }
        let hrvs = last7.compactMap { $0.avgHrv }
        let resps = last7.compactMap { $0.respRateBpm }
        let respCV: Double? = {
            guard resps.count >= 3 else { return nil }
            let mean = resps.reduce(0, +) / Double(resps.count)
            guard mean > 0 else { return nil }
            let variance = resps.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(resps.count)
            return variance.squareRoot() / mean
        }()
        return BiometricAgeEngine.compute(.init(
            chronoAge: Double(profile.age), sex: profile.sex,
            restingHR: rhrs.isEmpty ? nil : IntelligenceEngine.medianOf(rhrs),
            paIndex: pai,
            rmssd: hrvs.isEmpty ? nil : IntelligenceEngine.medianOf(hrvs),
            sleepHours: nights.isEmpty ? nil : nights.reduce(0, +) / Double(nights.count),
            sleepNeedHours: nil,
            sleepConsistency: VitalityEngine.sleepConsistency(nightlyHours: nights),
            trainingLoadRatio: trainingLoadRatio,
            respRateCV: respCV))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Baseline Age", overline: "In-house · Experimental",
                          trailing: result != nil ? String(localized: "vs age \(profile.age)") : nil)
            if let r = result {
                hero(r)
            } else if loaded {
                ComingSoon(what: "A few more days across HRV, sleep and training and we can show your Baseline Age.", symbol: "atom")
            } else {
                ComingSoon(what: "Reading your Baseline Age…", symbol: "atom")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private func load() async {
        trainingLoadRatio = (await repo.exploreSeries(key: "training_load_ratio", source: "my-whoop")).last?.value
        loaded = true
    }

    private func hero(_ r: BiometricAgeEngine.Result) -> some View {
        let younger = r.deltaYears >= 0
        let yrs = Int(abs(r.deltaYears).rounded())
        let worst = r.contributions.last   // highest (most-aging) delta
        let best = r.contributions.first   // lowest (most youth-favoring) delta
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: NoopMetrics.space5) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("Baseline Age").strandOverline()
                    CountUpText(value: r.biometricAge, format: { "\(Int($0.rounded()))" },
                                font: StrandFont.number(38), color: StrandPalette.textPrimary)
                    Text(deltaLine(yrs: yrs, younger: younger))
                        .font(StrandFont.footnote)
                        .foregroundStyle(younger ? StrandPalette.statusPositive : StrandPalette.statusWarning)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                    Text("Domains used").strandOverline()
                    Text("\(r.domainsUsed) of 5")
                        .font(StrandFont.number(20)).foregroundStyle(StrandPalette.textPrimary)
                }
            }
            Divider().overlay(StrandPalette.hairline)
            if let best, best.deltaYears < 0 {
                Text("Helping most: \(best.label)")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusPositive)
            }
            if let worst, worst.deltaYears > 0 {
                Text("Holding you back: \(worst.label)")
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.statusWarning)
            }
            Text("An original Baseline composite — cardio, HRV, sleep, training load and respiratory stability combined transparently. Not a clinical or medical estimate.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            FrostedCardSurface(tint: StrandPalette.metricRose, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    private func deltaLine(yrs: Int, younger: Bool) -> String {
        if yrs == 0 { return String(localized: "about your age") }
        switch (younger, yrs == 1) {
        case (true, true):   return String(localized: "1 yr younger")
        case (true, false):  return String(localized: "\(yrs) yrs younger")
        case (false, true):  return String(localized: "1 yr older")
        case (false, false): return String(localized: "\(yrs) yrs older")
        }
    }
}

// MARK: - Weekly / All-time divider

/// A plain-language seam between the two Fitness Age / Vitality readings so the split isn't only carried
/// by each card's small overline text. Both use the EXACT SAME StrandAnalytics formulas
/// (FitnessAgeEngine/VitalityEngine) — the only difference is the time window they're computed over:
/// the cards above use a rolling 7-day window, the cards below use your entire imported history in one
/// pass. Placed once, right where the window changes, so it's obvious without reading every card.
private struct HealthGroupDivider: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        HStack(spacing: NoopMetrics.space3) {
            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize()
            Rectangle().fill(StrandPalette.hairline).frame(height: 1)
        }
    }
}

// MARK: - Lifetime snapshot (full-history Fitness Age / Vitality, a separate category)

/// A SEPARATE category from the weekly Fitness Age/Vitality above: the same StrandAnalytics engines
/// (FitnessAgeEngine/VitalityEngine), but run over your ENTIRE imported history in one pass rather than a
/// rolling 7-day window (see IntelligenceEngine's "_lifetime"-suffixed compute). Deliberately never
/// blended into the weekly number — a multi-month average mixes "you a year ago" with "you now" into a
/// figure that isn't a fair read of either, so this is presented as its own, clearly-labeled comparison
/// point instead of a replacement.
private struct LifetimeSnapshotSection: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @State private var fitnessAge: Double?
    @State private var vitality: Double?
    @State private var bodyAge: Double?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Lifetime Averages", overline: "Full history",
                          trailing: fitnessAge != nil ? String(localized: "vs age \(profile.age)") : nil)
            if fitnessAge != nil || vitality != nil {
                card
            } else if loaded {
                ComingSoon(what: "Import more history and we can show your lifetime averages.", symbol: "infinity")
            } else {
                ComingSoon(what: "Reading your full history…", symbol: "infinity")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: NoopMetrics.space5) {
                if let fa = fitnessAge {
                    VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                        Text("Fitness Age").strandOverline()
                        Text("\(Int(fa.rounded()))")
                            .font(StrandFont.rounded(30))
                            .foregroundStyle(StrandPalette.chargeColor)
                    }
                }
                Spacer(minLength: 0)
                if let v = vitality, let ba = bodyAge {
                    VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                        Text("Vitality · Body Age").strandOverline()
                        Text("\(Int(v.rounded())) · \(Int(ba.rounded()))")
                            .font(StrandFont.number(20))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
            Divider().overlay(StrandPalette.hairline)
            Text("Computed from every day you've ever imported or synced, not just this week — a longer-window comparison point, never the number the weekly cards above are based on.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            FrostedCardSurface(tint: StrandPalette.metricPurple, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    private func load() async {
        fitnessAge = (await repo.exploreSeries(key: "fitness_age_lifetime", source: "my-whoop")).last?.value
        vitality = (await repo.exploreSeries(key: "vitality_lifetime", source: "my-whoop")).last?.value
        bodyAge = (await repo.exploreSeries(key: "body_age_lifetime", source: "my-whoop")).last?.value
        loaded = true
    }
}

// MARK: - PhenoAge (lab-panel biological age, Levine et al. 2018)

/// Reads the LATEST value of each of PhenoAgeEngine's nine required markers from the Lab Book (whichever
/// source they arrived from — manual entry, the markers CSV, or the new document scan) and, when a
/// complete panel is present, computes the published Levine et al. 2018 "Phenotypic Age". A partial panel
/// (e.g. a CBC with no CRP add-on) shows exactly which markers are still missing rather than a number
/// computed a different way — this formula is not designed to degrade gracefully like Baseline Age is.
private struct PhenoAgeSection: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var profile: ProfileStore
    @State private var latest: [String: LabMarkerRow] = [:]
    @State private var loaded = false

    private static let requiredKeys = [
        "albumin", "creatinine", "fasting_glucose", "crp", "lymphocyte_pct",
        "mcv", "rdw", "alkaline_phosphatase", "wbc_count",
    ]

    private var result: PhenoAgeEngine.Result? {
        func reading(_ key: String) -> PhenoAgeEngine.Reading? {
            guard let row = latest[key], let v = row.value else { return nil }
            return PhenoAgeEngine.Reading(value: v, unit: row.unit)
        }
        guard let albumin = reading("albumin"), let creatinine = reading("creatinine"),
              let glucose = reading("fasting_glucose"), let crp = reading("crp"),
              let lymph = reading("lymphocyte_pct"), let mcv = reading("mcv"),
              let rdw = reading("rdw"), let alp = reading("alkaline_phosphatase"),
              let wbc = reading("wbc_count"), profile.age > 0
        else { return nil }
        return PhenoAgeEngine.compute(.init(
            chronoAge: Double(profile.age), albumin: albumin, creatinine: creatinine, glucose: glucose,
            crp: crp, lymphocytePct: lymph, mcv: mcv, rdw: rdw, alkalinePhosphatase: alp, wbc: wbc))
    }

    private var missingLabels: [String] {
        Self.requiredKeys.filter { latest[$0]?.value == nil }
            .compactMap { MarkerCatalog.definition(for: $0)?.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("PhenoAge", overline: "From your lab panel",
                          trailing: result != nil ? String(localized: "vs age \(profile.age)") : nil)
            if let r = result {
                hero(r)
            } else if loaded {
                ComingSoon(what: LocalizedStringKey(!missingLabels.isEmpty
                           ? "Needs the rest of a full blood panel: \(missingLabels.joined(separator: ", ")). Add them in Lab Book."
                           : profile.age <= 0
                           ? "Add your age in Settings and we can show your PhenoAge."
                           : "One of your values looks out of range for this formula \u{2014} double-check your Lab Book entries against the report for a mis-scanned number or unit."),
                           symbol: "cross.vial")
                if loaded, result == nil, missingLabels.isEmpty, profile.age > 0 {
                    outOfRangeDiagnostics
                }
            } else {
                ComingSoon(what: "Reading your Lab Book…", symbol: "cross.vial")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    /// Shown only when all nine markers are present but the formula still rejected them — lists the raw
    /// stored value/unit for each so the user can spot the one a document scan misread (a stray digit or
    /// a swapped unit) without having to dig through the Lab Book row by row.
    private var outOfRangeDiagnostics: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            ForEach(Self.requiredKeys, id: \.self) { key in
                if let row = latest[key], let v = row.value {
                    HStack {
                        Text(MarkerCatalog.definition(for: key)?.displayName ?? key)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
                        Spacer()
                        Text("\(v.formatted()) \(row.unit ?? "")")
                            .font(StrandFont.footnote.weight(.medium)).foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
        }
        .padding(.top, NoopMetrics.space2)
    }

    private func hero(_ r: PhenoAgeEngine.Result) -> some View {
        let older = r.deltaYears >= 0
        let yrs = Int(abs(r.deltaYears).rounded())
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space5) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("PhenoAge").strandOverline()
                    CountUpText(value: r.phenoAge, format: { "\(Int($0.rounded()))" },
                                font: StrandFont.number(38), color: StrandPalette.textPrimary)
                }
                Spacer(minLength: 0)
                Text(deltaLine(yrs: yrs, older: older))
                    .font(StrandFont.footnote)
                    .foregroundStyle(older ? StrandPalette.statusWarning : StrandPalette.statusPositive)
            }
            Divider().overlay(StrandPalette.hairline)
            Text("Levine ME et al., \"An epigenetic biomarker of aging for lifespan and healthspan\", Aging (Albany NY) 2018 — the clinical-chemistry half of that paper (albumin, creatinine, glucose, CRP, and five CBC markers), not epigenetic. A published, externally-validated formula, reproduced exactly. Not a Baseline estimate, not medical advice.")
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            FrostedCardSurface(tint: StrandPalette.metricCyan, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    private func deltaLine(yrs: Int, older: Bool) -> String {
        if yrs == 0 { return String(localized: "about your age") }
        switch (older, yrs == 1) {
        case (true, true):   return String(localized: "1 yr older")
        case (true, false):  return String(localized: "\(yrs) yrs older")
        case (false, true):  return String(localized: "1 yr younger")
        case (false, false): return String(localized: "\(yrs) yrs younger")
        }
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rows = (try? await store.labMarkers(deviceId: repo.deviceId, category: LabMarkerCategory.bloodPanel.rawValue)) ?? []
        var byKey: [String: LabMarkerRow] = [:]
        for row in rows where Self.requiredKeys.contains(row.markerKey) {
            if let existing = byKey[row.markerKey], existing.takenAt >= row.takenAt { continue }
            byKey[row.markerKey] = row
        }
        latest = byKey
        loaded = true
    }
}

// MARK: - Training Load Balance

/// The "Training Load" section: this week's Acute:Chronic Workload Ratio (Gabbett 2016), a published
/// sports-science signal for whether recent training is climbing faster than the body has adapted to.
/// Reads the three MetricPoints IntelligenceEngine already persists (`training_load_ratio`/`_acute`/
/// `_chronic`) — no recomputation here, just an honest readback of the stored weekly snapshot. Shown
/// unconditionally on Health (not opt-in via "Your cards") so the feature isn't buried.
private struct TrainingLoadSection: View {
    @EnvironmentObject var repo: Repository
    @State private var ratio: Double?
    @State private var acute: Double?
    @State private var chronic: Double?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Training Load", overline: "Weekly",
                          trailing: ratio != nil ? String(format: "%.2f×", ratio!) : nil)
            if let r = ratio {
                hero(ratio: r)
            } else if loaded {
                ComingSoon(what: "A few more weeks of Effort data and we can show your Training Load.",
                           symbol: "gauge.with.dots.needle.67percent")
            } else {
                ComingSoon(what: "Reading your Training Load…", symbol: "gauge.with.dots.needle.67percent")
            }
        }
        .task(id: repo.refreshSeq) { await load() }
    }

    private func hero(ratio r: Double) -> some View {
        let tier = TrainingLoadEngine.tier(for: r)
        let tint: Color = {
            switch tier {
            case .low:      return StrandPalette.metricCyan
            case .balanced: return StrandPalette.chargeColor
            case .elevated: return StrandPalette.metricAmber
            case .high:     return StrandPalette.statusWarning
            }
        }()
        return VStack(alignment: .leading, spacing: NoopMetrics.space4) {
            HStack(alignment: .center, spacing: NoopMetrics.space5) {
                VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                    Text("This week").strandOverline()
                    Text(tier.label)
                        .font(StrandFont.rounded(30))
                        .foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                if let a = acute, let c = chronic {
                    VStack(alignment: .trailing, spacing: NoopMetrics.space1) {
                        Text("7-day vs 28-day avg").strandOverline()
                        Text("\(Int(a.rounded())) vs \(Int(c.rounded()))")
                            .font(StrandFont.number(20))
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
            }
            Divider().overlay(StrandPalette.hairline)
            Text(explainer(for: tier))
                .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
        }
        .padding(NoopMetrics.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            FrostedCardSurface(tint: tint, cornerRadius: NoopMetrics.cardRadius)
        }
        .clipShape(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training Load: \(tier.label), ratio \(String(format: "%.2f", r))")
    }

    /// Plain-language read of the tier, same spirit as the ComingSoon copy elsewhere — never framed as
    /// medical advice, just the published heuristic in a sentence.
    private func explainer(for tier: TrainingLoadEngine.Tier) -> String {
        switch tier {
        case .low:
            return "This week's Effort is well below your last month's norm — easing off or recovering."
        case .balanced:
            return "This week's Effort is tracking your last month's norm — a sustainable ramp."
        case .elevated:
            return "This week's Effort is climbing faster than your last month's norm. Not a problem on its own, but worth watching."
        case .high:
            return "This week's Effort is climbing well above your last month's norm — published research on this ratio links a spike this size to a higher injury rate."
        }
    }

    private func load() async {
        ratio = (await repo.exploreSeries(key: "training_load_ratio", source: "my-whoop")).last?.value
        acute = (await repo.exploreSeries(key: "training_load_acute", source: "my-whoop")).last?.value
        chronic = (await repo.exploreSeries(key: "training_load_chronic", source: "my-whoop")).last?.value
        loaded = true
    }
}

// MARK: - Vitals grid (uniform StatTiles)

/// Static vitals grid, split into its own view so it depends only on `repo` and is
/// not re-rendered by the ~1Hz live HR stream.
private struct VitalsSection: View {
    @EnvironmentObject var repo: Repository

    // Temperature display preference (D#103). Skin temp is stored in °C (absolute or a ±deviation); the
    // toggle re-labels it to °F. Display-only — banding still runs on the stored °C value.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.temperatureKey) private var temperatureRaw = ""
    private var temperatureUnit: TemperatureUnit {
        let system = UnitSystem(rawValue: unitSystemRaw) ?? .metric
        return UnitPrefs.resolveTemperature(system: system, override: temperatureRaw)
    }

    var body: some View {
        let readings = BodyVitalSigns.readings(
            sourceRows: repo.vitalMetricRows,
            temperatureUnit: temperatureUnit
        )
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Vital Signs", overline: "Latest", trailing: BodyVitalSigns.latestDayLabel(readings))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)],
                alignment: .leading,
                spacing: NoopMetrics.gap
            ) {
                ForEach(Array(readings.enumerated()), id: \.element.id) { idx, v in
                    // Each headline vital is now a liquid tile: the signature LiquidVessel gauge tinted
                    // to the metric's colour world (rose RHR, purple HRV, cyan SpO₂, amber skin temp),
                    // filled to the metric's fraction, with the value counting up beside it and the same
                    // banding caption + sparkline the classic tile carried. Every binding + accessibility
                    // label is preserved — this is the liquid restyle of the flat StatTile.
                    LiquidVitalTile(reading: v)
                        .staggeredAppear(index: idx)
                }
            }
            Text("Once Baseline has 14 nights of history, in-range compares each vital to your own baseline (approximate, not medical advice); until then, typical adult ranges apply.")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Liquid vital tile (vessel gauge + count-up value + banding caption + spark trail)

/// One headline vital sign rendered in the liquid finish: a metric-tinted `LiquidVessel` gauge (filled
/// to the vital's physiological fraction), the value counting up beside it, the banded state caption, and
/// the same sparkline trail the classic StatTile drew. A frosted `NoopCard` tinted to the metric's accent,
/// matching Today's Key-Metrics tiles. Presentation-only: value, banding and source are unchanged — this
/// just gives each vital a real liquid gauge instead of a flat tile.
private struct LiquidVitalTile: View {
    let reading: BodyVitalReading

    var body: some View {
        NoopCard(padding: 14, tint: reading.accent) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(reading.label)").strandOverline()
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 10) {
                    // The signature liquid gauge — static (posed) so a grid of them doesn't each run a live
                    // 30fps Canvas. nil fraction (no value) reads as an empty vessel, no fabricated fill.
                    LiquidVessel(value: vesselFraction, tint: reading.metricColor, animated: false)
                        .frame(width: 34, height: 34)
                    if let value = reading.value {
                        // The value counts up on appear (snaps under Reduce Motion), formatted exactly as
                        // the classic tile did (the reading's own formatter + unit), so it's byte-identical.
                        CountUpText(value: value,
                                    format: { "\(reading.format($0)) \(reading.unit)" },
                                    font: StrandFont.number(24),
                                    color: reading.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("—").font(StrandFont.number(24)).foregroundStyle(reading.accent)
                    }
                    Spacer(minLength: 0)
                }
                #if !os(watchOS)
                if let sparkline = reading.sparkline, sparkline.count > 1 {
                    Sparkline(values: sparkline, gradient: Gradient(colors: [reading.metricColor.opacity(0.5), reading.metricColor]))
                        .frame(height: 22).padding(.top, 6)
                        .accessibilityHidden(true)
                }
                #endif
                Text(reading.stateCaption)
                    .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
                    .padding(.top, 4)
            }
        }
        .frame(minHeight: NoopMetrics.tileHeight, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityText)
    }

    /// The vessel's fill (0…1): the vital's value mapped onto its physiological span, matching Today's
    /// per-metric `fracOver` denominators (HRV/120, RHR/100, respiratory/24, SpO₂ across 90…100, absolute
    /// skin temp across 33…38 °C). nil when there's no value, so the gauge reads empty rather than faked.
    private var vesselFraction: Double? {
        guard let v = reading.value else { return nil }
        func over(_ span: Double) -> Double { max(0.02, min(1, v / span)) }
        func across(_ lo: Double, _ hi: Double) -> Double { max(0.02, min(1, (v - lo) / (hi - lo))) }
        switch reading.key {
        case "hrv":        return over(120)
        case "rhr":        return over(100)
        case "resp_rate":  return over(24)
        case "spo2":       return across(90, 100)
        case "skin_temp":
            // Absolute skin temp (>= 20 °C) maps across a plausible wrist band; a small ±deviation
            // maps around a half-full centre so a normal night reads mid-gauge, not empty.
            return VitalBands.isAbsoluteSkinTemp(v) ? across(33, 38) : max(0.02, min(1, 0.5 + v / 4))
        default:           return across(0, max(1, v * 1.5))
        }
    }
}

// MARK: - Skin-temperature suite (v5: illness heads-up · body clock · cycle awareness)

/// The v5 skin-temperature section: the confounder-suppressed illness "heads-up", the body-clock
/// estimate, and the OPT-IN cycle awareness card — each rendered from a pure StrandAnalytics engine
/// result the analytics pass computed and `AppModel` publishes. Honest throughout: the heads-up only
/// shows when the engine returns a non-quiet level; cycle awareness shows the opt-in card until the user
/// turns it on (default OFF); the body clock shows nil-state copy until it can read a rhythm.
private struct SkinTempSection: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var repo: Repository

    /// The cycle-awareness opt-in (default OFF). The same key AppModel reads, so a flip is consistent.
    @AppStorage(AppModel.cycleAwarenessKey) private var cycleEnabled = false

    /// Whether the cycle-awareness opt-in is offered for this profile (#801). Delegates to the shared
    /// ``ProfileStore/cycleAwarenessApplies`` gate so Health + Automations stay in lockstep: cycle phase
    /// is read from the menstrual skin-temperature shift, so the opt-in is NOT shown for male profiles.
    private var cycleOptInApplies: Bool { model.profile.cycleAwarenessApplies }

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Skin temperature", overline: "From your nightly sensor")

            // 1. Illness heads-up — only when the engine returned something worth surfacing.
            if let illness = model.illnessSignal, illness.level != .quiet {
                HeadsUpCard(result: illness, distance: model.illnessDistance)
            }

            // 2. Body clock — shows nil-state copy via the engine's own confidence handling.
            if let phase = model.circadianPhase {
                BodyClockCard(estimate: phase)
            }

            // 3. Cycle awareness: opt-in, and gated on profile sex (#801). Cycle phase is derived
            // from the menstrual temperature shift, so the opt-in is only offered to profiles it can
            // apply to (female / nonbinary); it is NOT rendered for male profiles. If a profile that
            // previously enabled it later switches to male, we still honour the existing awareness card
            // rather than silently hiding their data; only the OPT-IN invitation is gated.
            if cycleEnabled, let cycle = model.cyclePhase {
                CycleAwarenessCard(result: cycle, curve: model.cycleCurve,
                                   // Symmetric off (#801): turn it off in-place, here in Health, where
                                   // it was turned on, not only from Automations.
                                   onTurnOff: {
                                       cycleEnabled = false
                                       model.cycleAwarenessEnabled = false
                                       Task { await model.refreshV5Signals() }
                                   })
            } else if !cycleEnabled && cycleOptInApplies {
                CycleAwarenessOptInCard(onEnable: {
                    cycleEnabled = true
                    model.cycleAwarenessEnabled = true
                    Task { await model.refreshV5Signals() }
                })
            }

            // Honest empty state when the suite has nothing to show yet. The opt-in card normally fills
            // the section when cycle is OFF, but it is gated off for male profiles (#801), so the
            // section can also be blank when the opt-in doesn't apply AND nothing else has data. Show
            // the empty state in either case (cycle ON but thin, OR opt-in hidden with no other signal).
            if (cycleEnabled || !cycleOptInApplies)
                && model.illnessSignal == nil && model.circadianPhase == nil && model.cyclePhase == nil {
                ComingSoon(what: "Wear the strap overnight and these read from your nightly skin temperature.",
                           symbol: "thermometer.medium")
            }
        }
    }
}

// MARK: - Health hub deep-links (Lab Book · Your Data, Fused)

/// Two drill-in rows that give the records logbook (Lab Book) and the multi-device fused record their
/// honest Health home without making either its own top-level destination — they route via `NavRouter`
/// (the macOS sidebar selects the item; iOS presents the pillar sheet).
private struct HealthHubLinksSection: View {
    @EnvironmentObject var router: NavRouter

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Records & sources", overline: "On \(Platform.deviceNounPhrase)")
            linkRow(title: String(localized: "Lab Book"),
                    subtitle: String(localized: "Keep your bloods, BP and body numbers private, on \(Platform.deviceNounPhrase)."),
                    symbol: "books.vertical.fill", tint: StrandPalette.metricCyan) { router.openLabBook() }
            linkRow(title: String(localized: "Your Data, Fused"),
                    subtitle: String(localized: "The best-sourced number per metric across every band you use."),
                    symbol: "square.stack.3d.up.fill", tint: StrandPalette.accent) { router.openFusedRecord() }
        }
    }

    private func linkRow(title: String, subtitle: String, symbol: String, tint: Color,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NoopCard {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(subtitle)
                            .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        // Liquid press response — every tappable liquid card settles inward on touch (matches Today).
        .buttonStyle(LiquidPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Health Monitor") {
    let repo = Repository(deviceId: "preview")
    repo.days = [
        DailyMetric(
            day: "2026-06-06",
            totalSleepMin: 462, efficiency: 92,
            deepMin: 96, remMin: 108, lightMin: 240, disturbances: 7,
            restingHr: 52, avgHrv: 74, recovery: 81, strain: 11.4,
            exerciseCount: 1,
            spo2Pct: 97, skinTempDevC: 34.2, respRateBpm: 14.6
        )
    ]
    repo.loaded = true

    let live = LiveState()
    live.connected = true
    live.bonded = true
    live.heartRate = 132
    live.rr = [455, 460, 448, 470, 452, 461, 449, 458, 463, 451]

    return HealthView()
        .environmentObject(repo)
        .environmentObject(live)
        .environmentObject(ProfileStore())
        .environmentObject(AppModel())
        .environmentObject(NavRouter())
        .frame(width: 900, height: 760)
        .preferredColorScheme(.dark)
}

/// Deterministic render target for `--demo-screen fitnessage` (pair with `--demo-seed` to populate the
/// weekly value). Shows the REAL `FitnessAgeSection` on the production scaffold, so a screenshot matches
/// what ships. Reads the same injected `repo`/`profile` environment objects as the live app.
struct FitnessAgeDemoScreen: View {
    var body: some View {
        ScreenScaffold(title: "Health Monitor", subtitle: "Fitness Age", onRefresh: {}) {
            FitnessAgeSection()
        }
    }
}

/// Deterministic render target for `--demo-screen vitality` (pair with `--demo-seed`).
struct VitalityDemoScreen: View {
    var body: some View {
        ScreenScaffold(title: "Health Monitor", subtitle: "Vitality", onRefresh: {}) {
            VitalitySection()
        }
    }
}
#endif
