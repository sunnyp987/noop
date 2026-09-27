import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - WHOOP Cloud comparison (PRIVATE — not a public Baseline feature)
//
// This screen exists ONLY in this user's own build, for as long as their WHOOP subscription is
// active. It is intentionally NOT linked from primary navigation, NOT mentioned in CHANGELOG.md or
// the AltStore source description — reachable only via a long-press on "ADVANCED" in Test Centre.
// Baseline's public identity is "no WHOOP app, no subscription, no cloud" (see ATTRIBUTION.md /
// altstore-source.json); this tool intentionally steps outside that identity for one person, one
// build, one purpose: pull WHOOP's own cloud-computed numbers via their real OAuth API and diff
// them, day by day, against Baseline's own independently-computed numbers for the same strap — to
// validate Baseline's algorithms, spot concrete discrepancies worth investigating, and judge which
// source (official API vs Baseline's own BLE extraction) reads as the steadier day-to-day signal.
//
// BYO OAuth credentials: the user creates their own app in the WHOOP Developer Dashboard
// (developer.whoop.com) and pastes its Client ID/Secret here, mirroring the AI Coach's "paste your
// own key" pattern. Nothing is embedded in the app; nothing is shared with anyone else's install.
struct WhoopCloudCompareView: View {
    @EnvironmentObject var model: AppModel

    @State private var clientId: String = WhoopCloudAuthStore.clientId ?? ""
    @State private var clientSecret: String = WhoopCloudAuthStore.clientSecret ?? ""
    @State private var isConnected = WhoopCloudAuthStore.isConnected
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var report: WhoopCloudComparisonReport?
    @State private var reportLines: [String] = WhoopCloudSyncScheduler.lastReportLines
    @State private var syncEnabled = WhoopCloudSyncScheduler.isEnabled
    @State private var interval = WhoopCloudSyncScheduler.interval

    // Historical CSV backfill — deliberately a SEPARATE report from the live API one (see
    // WhoopCloudCSVImport.swift's header): the manual export and the live API are the same
    // underlying WHOOP data, so this never merges into `report`, only stands beside it.
    @State private var showCSVImporter = false
    @State private var historicalReport: WhoopCloudComparisonReport?
    @State private var historicalError: String?

    var body: some View {
        ScreenScaffold(title: "WHOOP Cloud Compare",
                       subtitle: "Personal validation tool. Compares WHOOP's own cloud numbers against Baseline's own computed numbers for the same days.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                credentialsCard
                connectionCard
                if isConnected {
                    scheduleCard
                    reportCard
                }
                historicalImportCard
            }
        }
        .fileImporter(isPresented: $showCSVImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            Task { await importHistoricalCSV(result) }
        }
        .alert("WHOOP Cloud error", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Import error", isPresented: .init(get: { historicalError != nil }, set: { if !$0 { historicalError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(historicalError ?? "")
        }
    }

    // MARK: - Historical CSV backfill (separate report, see header note above)

    private var historicalImportCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("HISTORICAL BACKFILL (MANUAL EXPORT)").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text("Same WHOOP data as the live API, just further back. From WHOOP app: Settings -> Get your data, unzip it, then pick physiological_cycles.csv here. Shown as its own separate report below, never merged with the live one above, so a stale export can't quietly blend into current numbers.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Import physiological_cycles.csv") { showCSVImporter = true }
                    .buttonStyle(.bordered)

                if let historicalReport {
                    Divider().overlay(StrandPalette.hairline)
                    Text("\(historicalReport.windowStart) to \(historicalReport.windowEnd)")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    ForEach(historicalReport.summaryLines, id: \.self) { line in
                        Text(line).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Client credentials (BYO, same pattern as AI Coach)

    private var credentialsCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("YOUR WHOOP DEVELOPER APP").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text("Create an app at developer.whoop.com, set its redirect URL to baseline-whoop://oauth/callback, then paste its Client ID and Secret below.")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Client ID", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                SecureField("Client Secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)

                Button("Save credentials") {
                    WhoopCloudAuthStore.saveClientCredentials(id: clientId, secret: clientSecret)
                }
                .buttonStyle(.bordered)
                .disabled(clientId.trimmingCharacters(in: .whitespaces).isEmpty ||
                          clientSecret.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Connect / disconnect

    private var connectionCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("CONNECTION").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)

                HStack {
                    Circle().fill(isConnected ? Color.green : StrandPalette.textTertiary).frame(width: 8, height: 8)
                    Text(isConnected ? "Connected — auto-refreshes silently, no re-login needed" : "Not connected")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                }

                if isConnected {
                    Button("Disconnect", role: .destructive) {
                        WhoopCloudAPI.disconnect()
                        WhoopCloudSyncScheduler.setEnabled(false)
                        isConnected = false
                        syncEnabled = false
                        report = nil
                        reportLines = []
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        if isBusy { ProgressView() } else { Text("Connect to WHOOP") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || WhoopCloudAuthStore.clientId == nil || WhoopCloudAuthStore.clientSecret == nil)
                }
            }
        }
    }

    // MARK: - Sync schedule: Daily / Weekly toggle + manual Sync now

    private var scheduleCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("SYNC SCHEDULE").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)

                Toggle(isOn: $syncEnabled) {
                    Text("Auto-sync in the background").font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch).tint(StrandPalette.accent)
                .onChangeCompat(of: syncEnabled) { on in WhoopCloudSyncScheduler.setEnabled(on) }

                if syncEnabled {
                    Picker("Interval", selection: $interval) {
                        Text("Daily").tag(WhoopCloudSyncScheduler.Interval.daily)
                        Text("Weekly").tag(WhoopCloudSyncScheduler.Interval.weekly)
                    }
                    .pickerStyle(.segmented)
                    .onChangeCompat(of: interval) { WhoopCloudSyncScheduler.setInterval($0) }
                }

                if let last = WhoopCloudSyncScheduler.lastRunAt {
                    Text("Last synced \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }

                Button {
                    Task { await syncNow() }
                } label: {
                    if isBusy { ProgressView() } else { Text("Sync now") }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    // MARK: - Latest comparison report

    private var reportCard: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                Text("LATEST COMPARISON").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textSecondary)

                if reportLines.isEmpty {
                    Text("No comparison yet. Tap Sync now.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textTertiary)
                } else {
                    ForEach(reportLines, id: \.self) { line in
                        Text(line).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func connect() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await WhoopCloudAPI.connect()
            isConnected = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNow() async {
        isBusy = true
        defer { isBusy = false }
        guard let deviceId = model.deviceRegistry?.activeDeviceId, let store = await model.repo.rawStoreHandle() else {
            errorMessage = "Baseline's own metrics store isn't ready yet."
            return
        }
        do {
            let result = try await WhoopCloudSyncScheduler.runNow(deviceId: deviceId, store: store)
            report = result
            reportLines = result.summaryLines
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importHistoricalCSV(_ result: Result<URL, Error>) async {
        guard let deviceId = model.deviceRegistry?.activeDeviceId, let store = await model.repo.rawStoreHandle() else {
            historicalError = "Baseline's own metrics store isn't ready yet."
            return
        }
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let cloudDays = try WhoopCloudCSVImport.parseCloudDays(fileAt: url)
            guard let fromDay = cloudDays.keys.min(), let toDay = cloudDays.keys.max() else { return }

            let computedId = deviceId + "-noop"
            let localRows = (try? await store.dailyMetrics(deviceId: computedId, from: fromDay, to: toDay)) ?? []
            var baselineDays: [String: BaselineDayValues] = [:]
            for row in localRows {
                baselineDays[row.day] = BaselineDayValues(
                    restingHr: row.restingHr.map(Double.init), hrv: row.avgHrv, recovery: row.recovery,
                    strain: row.strain, sleepPerformance: row.efficiency)
            }
            historicalReport = WhoopCloudComparisonEngine.compare(baselineDays: baselineDays, cloudDays: cloudDays)
        } catch {
            historicalError = error.localizedDescription
        }
    }
}
