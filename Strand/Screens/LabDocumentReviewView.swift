import SwiftUI
import StrandDesign
import StrandImport
import StrandAnalytics
import WhoopStore

// MARK: - Lab Book document-scan review (source "lab-document")
//
// LabDocumentReviewView.swift — the mandatory checkpoint between a scanned PDF/photo and
// anything actually written to the Lab Book. LabResultDocumentImport is a best-effort,
// text-layout-dependent parser (see its own file header); this screen is what keeps that
// honest: every detected row is shown back — as printed, and as parsed — with a toggle to
// keep or drop it, before a single value is saved. Nothing here is auto-accepted.
//
// Mirrors the app's existing non-clinical stance: no row is judged, no unit is converted,
// the collection date is editable (a report carries one date for the whole panel, and OCR
// sometimes misses it entirely).
struct LabDocumentReviewView: View {
    let result: LabResultDocumentImport.Result
    let deviceId: String
    let onSave: (_ rows: [LabMarkerRow]) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var day: String
    @State private var included: Set<Int>
    @State private var saving = false

    init(result: LabResultDocumentImport.Result, deviceId: String, onSave: @escaping (_ rows: [LabMarkerRow]) async -> Void) {
        self.result = result
        self.deviceId = deviceId
        self.onSave = onSave
        _day = State(initialValue: result.detectedDay ?? LabBookFormat.dayKey(Date()))
        _included = State(initialValue: Set(result.rows.indices))
    }

    var body: some View {
        ScreenScaffold(title: "Review scan", subtitle: "Check these against your report before saving.") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                noticeCard
                dateCard
                if result.rows.isEmpty {
                    emptyState
                } else {
                    rowsCard
                }
                saveButton
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #else
        .frame(width: 560, height: 720)
        #endif
        .background(StrandPalette.surfaceBase)
    }

    // MARK: - Notice

    private var noticeCard: some View {
        NoopCard(tint: StrandPalette.metricAmber) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.viewfinder")
                        .foregroundStyle(StrandPalette.metricAmber)
                    Text("Best-effort scan").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                }
                Text(noticeText)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noticeText: String {
        var s = "Baseline read this document on \(Platform.deviceNounPhrase) — nothing was sent anywhere. Only names it recognises from your Lab Book catalog are shown below; anything it wasn't sure about is left out rather than guessed."
        if result.unrecognizedLineCount > 0 {
            s += result.unrecognizedLineCount == 1
                ? " 1 line looked like a result but didn't match a known marker."
                : " \(result.unrecognizedLineCount) lines looked like results but didn't match a known marker."
        }
        if result.truncated {
            s += " The document was long enough that the end of it wasn't read."
        }
        return s
    }

    // MARK: - Date

    private var dateCard: some View {
        NoopCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collection date").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text(result.detectedDay == nil ? "Not found in the document — check this" : "Found in the document — check this")
                        .font(StrandFont.footnote)
                        .foregroundStyle(result.detectedDay == nil ? StrandPalette.statusWarning : StrandPalette.textTertiary)
                }
                Spacer()
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { LabDocumentReviewView.dayFormatter.date(from: day) ?? Date() },
            set: { day = LabBookFormat.dayKey($0) }
        )
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Detected rows

    private var rowsCard: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Detected readings", overline: included.count == 1 ? "1 selected" : "\(included.count) selected")
            NoopCard {
                VStack(spacing: 0) {
                    ForEach(Array(result.rows.enumerated()), id: \.offset) { idx, row in
                        rowView(idx, row)
                        if idx < result.rows.count - 1 {
                            Divider().overlay(StrandPalette.hairline)
                        }
                    }
                }
            }
        }
    }

    private func rowView(_ idx: Int, _ row: LabResultDocumentImport.DetectedRow) -> some View {
        let isOn = included.contains(idx)
        return Button {
            if isOn { included.remove(idx) } else { included.insert(idx) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? StrandPalette.accent : StrandPalette.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(for: row)).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text(valueLine(row)).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Text("as printed: \(row.rawLine)")
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .opacity(isOn ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(for: row)), \(valueLine(row)), \(isOn ? "included" : "excluded")")
    }

    private func title(for row: LabResultDocumentImport.DetectedRow) -> String {
        switch row.kind {
        case .marker(let key, _, _): return MarkerCatalog.definition(for: key)?.displayName ?? LabBookView.humanise(key)
        case .bloodPressure: return MarkerCatalog.definition(for: LabBookProjection.bpSystolicKey)?.displayName ?? "Blood pressure"
        }
    }

    private func valueLine(_ row: LabResultDocumentImport.DetectedRow) -> String {
        switch row.kind {
        case .marker(let key, _, let v):
            return "\(LabBookFormat.value(v, key: key)) \(row.unit)"
        case .bloodPressure(let sys, let dia):
            return "\(Int(sys.rounded()))/\(Int(dia.rounded())) \(row.unit)"
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing recognised").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text("Baseline couldn't match any line in this document to a known marker. You can still add readings by hand, or bring in a markers CSV instead.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            Task {
                saving = true
                await onSave(buildRows())
                saving = false
                dismiss()
            }
        } label: {
            Label(saving ? "Saving…" : "Save selected readings", systemImage: "checkmark")
        }
        .buttonStyle(.noopPrimary)
        .disabled(saving || included.isEmpty)
    }

    private func buildRows() -> [LabMarkerRow] {
        let epoch = LabBookFormat.noonEpoch(day)
        var rows: [LabMarkerRow] = []
        for (idx, row) in result.rows.enumerated() where included.contains(idx) {
            switch row.kind {
            case .marker(let key, let category, let v):
                rows.append(LabMarkerRow(
                    id: "\(key)-\(epoch)-\(UUID().uuidString.prefix(8))",
                    deviceId: deviceId, markerKey: key, category: category.rawValue, day: day,
                    takenAt: epoch, value: v, valueText: nil, unit: row.unit,
                    source: LabResultDocumentImport.sourceId, note: nil, referenceText: row.referenceText))
            case .bloodPressure(let sys, let dia):
                rows.append(LabMarkerRow(
                    id: "\(LabBookProjection.bpSystolicKey)-\(epoch)-\(UUID().uuidString.prefix(8))",
                    deviceId: deviceId, markerKey: LabBookProjection.bpSystolicKey, category: LabMarkerCategory.bloodPressure.rawValue,
                    day: day, takenAt: epoch, value: sys, valueText: nil, unit: row.unit,
                    source: LabResultDocumentImport.sourceId, note: nil, referenceText: row.referenceText))
                rows.append(LabMarkerRow(
                    id: "\(LabBookProjection.bpDiastolicKey)-\(epoch)-\(UUID().uuidString.prefix(8))",
                    deviceId: deviceId, markerKey: LabBookProjection.bpDiastolicKey, category: LabMarkerCategory.bloodPressure.rawValue,
                    day: day, takenAt: epoch, value: dia, valueText: nil, unit: row.unit,
                    source: LabResultDocumentImport.sourceId, note: nil, referenceText: row.referenceText))
            }
        }
        return rows
    }
}
