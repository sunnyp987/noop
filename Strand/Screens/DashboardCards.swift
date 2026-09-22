import Foundation
import SwiftUI

// MARK: - "Your cards" customisable dashboard (WHOOP "My Dashboard")
//
// The Today screen's "Your cards" section was a fixed trio (Stress / Fitness age / Vitality). This turns
// it into a user-customisable dashboard faithful to WHOOP's "My Dashboard": the user chooses WHICH metric
// cards show and in WHAT order from a registry of the values Today already loads. Persistence is
// DISPLAY-ONLY, no metric is computed or stored differently; this just decides which already-loaded
// values render as WHOOP metric rows and in what sequence.
//
// Stored as a JSON-encoded [String] of card ids in @AppStorage (UserDefaults). Unknown ids are dropped on
// read; a known id missing from the saved list is offered (disabled) in the editor so a future card can't
// be lost. Mirrors the existing KeyMetric layout mechanism but as its own list so the two sections stay
// independent (Key Metrics grid vs. the Your-cards dashboard).

/// One available card in the "Your cards" dashboard. The `rawValue` is the stable persisted identifier,
/// keep it byte-identical to the Android `DashboardCard` ids so a backup/restore reads the same dashboard
/// on either OS.
enum DashboardCard: String, CaseIterable, Identifiable {
    case hrv
    case restingHr
    case respiratory
    case steps
    case stress
    case fitnessAge
    case vitality
    /// VO2max estimate (Nes/HUNT model, StrandAnalytics FitnessAgeEngine), in mL/kg/min — the SAME unit
    /// WHOOP's own app reports, so a number from either app reads on the same scale. Already computed
    /// (as "vo2max_est") and shown on the Health screen's Fitness Age section; this surfaces it as its
    /// own dashboard card too, since it wasn't obviously discoverable there.
    case vo2max
    /// Training Load Balance (Acute:Chronic Workload Ratio, StrandAnalytics TrainingLoadEngine): whether
    /// this week's Effort/Strain is climbing faster than the last month's norm, a published (Gabbett
    /// 2016) sports-science signal several cohort studies associate with higher injury rates when
    /// pushed too high. A genuinely new metric, not currently shown anywhere else in the app.
    case trainingLoad
    case bloodOxygen
    case skinTemp
    case sleep
    case calories
    case hydration
    /// Optional, default-OFF (task #43): a tap-through to the Coupled view (the WHOOP-style day read). Unlike
    /// every other card this carries NO metric value of its own, it is a navigation row that opens the full
    /// CoupledView screen. It is NOT in `defaultSelection`, so a fresh install never shows it until the user
    /// adds it via CUSTOMISE, matching the manual-first / default-OFF posture.
    case coupled
    /// Optional, default-OFF: a tap-through shortcut straight to the Interval Timer, for anyone who runs
    /// intervals often and would rather tap one dashboard row than dig through the tab bar. Like `.coupled`
    /// this carries NO metric value of its own — a pure navigation row — so it is NOT in `defaultSelection`.
    case intervals

    var id: String { rawValue }

    /// The card's display label (the UPPERCASE WHOOP metric-row label is derived from this). Localized via
    /// the String Catalog so the dashboard rows read in the user's language (the `.uppercased()` the row
    /// applies then uppercases the LOCALIZED word, with the current locale's casing rules).
    var title: String {
        switch self {
        case .hrv:         return String(localized: "HRV")
        case .restingHr:   return String(localized: "Resting HR")
        case .respiratory: return String(localized: "Respiratory")
        case .steps:       return String(localized: "Steps")
        case .stress:      return String(localized: "Stress")
        case .fitnessAge:  return String(localized: "Fitness Age")
        case .vitality:    return String(localized: "Vitality")
        case .vo2max:      return String(localized: "VO2 Max")
        case .trainingLoad: return String(localized: "Training Load")
        case .bloodOxygen: return String(localized: "Blood Oxygen")
        case .skinTemp:    return String(localized: "Skin Temp")
        case .sleep:       return String(localized: "Sleep")
        case .calories:    return String(localized: "Calories")
        case .hydration:   return String(localized: "Hydration")
        case .coupled:     return String(localized: "Coupled view")
        case .intervals:   return String(localized: "Intervals")
        }
    }

    /// A short grey baseline/caption shown under the row's value (the WHOOP "30-day baseline" line).
    /// Static descriptive text only, never invented data. Localized via the String Catalog.
    var subtitle: String {
        switch self {
        case .hrv:         return String(localized: "Heart-rate variability")
        case .restingHr:   return String(localized: "Resting heart rate")
        case .respiratory: return String(localized: "Breaths per minute")
        case .steps:       return String(localized: "Today")
        case .stress:      return String(localized: "Autonomic load")
        case .fitnessAge:  return String(localized: "Updated weekly")
        case .vitality:    return String(localized: "Wellness score")
        case .vo2max:      return String(localized: "Estimated aerobic fitness")
        case .trainingLoad: return String(localized: "This week vs your last month")
        case .bloodOxygen: return String(localized: "Blood oxygen")
        case .skinTemp:    return String(localized: "Skin temperature")
        case .sleep:       return String(localized: "Last night")
        case .calories:    return String(localized: "Active energy")
        case .hydration:   return String(localized: "Today's fluid")
        case .coupled:     return String(localized: "Recovery, strain and sleep in one glance")
        case .intervals:   return String(localized: "Jump straight to the timer")
        }
    }

    /// The thin-line SF Symbol shown in the leading icon tile.
    var icon: String {
        switch self {
        case .hrv:         return "waveform.path.ecg"
        case .restingHr:   return "heart.fill"
        case .respiratory: return "lungs.fill"
        case .steps:       return "figure.walk"
        case .stress:      return "bolt.heart"
        case .fitnessAge:  return "figure.run"
        case .vitality:    return "sparkles"
        case .vo2max:      return "lungs.fill"
        case .trainingLoad: return "gauge.with.dots.needle.67percent"
        case .bloodOxygen: return "drop.fill"
        case .skinTemp:    return "thermometer.medium"
        case .sleep:       return "bed.double.fill"
        case .calories:    return "flame.fill"
        case .hydration:   return "drop.fill"
        case .coupled:     return "circle.hexagongrid.fill"
        case .intervals:   return "timer"
        }
    }

    /// The unit suffix shown after the value (smaller weight). Empty when the value is already complete.
    var unit: String {
        switch self {
        case .hrv:         return "ms"
        case .restingHr:   return "bpm"
        case .respiratory: return "rpm"
        case .steps:       return ""
        case .stress:      return ""
        case .fitnessAge:  return "yrs"
        case .vitality:    return ""
        case .vo2max:      return "mL/kg/min"
        case .trainingLoad: return ""    // value is a plain-language tier, e.g. "Balanced", not a raw number
        case .bloodOxygen: return ""    // value carries the % itself
        case .skinTemp:    return ""    // value carries the ° itself
        case .sleep:       return ""    // value carries the h/m itself
        case .calories:    return "kcal"
        case .hydration:   return ""    // value bakes in "<total> / <goal> L" itself
        case .coupled:     return ""    // a tap-through row, no value, so no unit
        case .intervals:   return ""    // a tap-through row, no value, so no unit
        }
    }

    /// The default set when the user hasn't customised the dashboard: the original Stress / Fitness age /
    /// Vitality trio plus HRV + Resting HR (per the task's "sensible default"). Cards with no value yet
    /// simply render "—", so the default set is safe on a fresh install.
    static let defaultSelection: [DashboardCard] = [
        .stress, .fitnessAge, .vitality, .hrv, .restingHr,
    ]

    /// Canonical order used to list the disabled remainder in the editor.
    static let canonicalOrder: [DashboardCard] = allCases
}

/// Display-only persistence for the "Your cards" dashboard selection. Holds an ORDERED list of the enabled
/// cards as a JSON-encoded [String] of ids; a card not in the list is hidden. Stored in
/// @AppStorage("today.dashboardCards").
enum DashboardCardPrefs {
    /// UserDefaults key, a JSON array of `DashboardCard` ids in display order.
    static let selectionKey = "today.dashboardCards"

    /// Encode an ordered list of enabled cards into the stored JSON string. Falls back to a comma-joined
    /// string if JSON encoding ever fails (it won't for [String]), so the value is always decodable.
    static func encode(_ cards: [DashboardCard]) -> String {
        let ids = cards.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids), let json = String(data: data, encoding: .utf8) {
            return json
        }
        return ids.joined(separator: ",")
    }

    /// Decode the stored string into an ordered list of enabled cards. An empty/unset string yields the
    /// default selection (so a fresh install shows the sensible default). Accepts both the JSON-array form
    /// and a legacy comma-joined form. Unknown ids are dropped; duplicates are de-duped; this returns ONLY
    /// the enabled cards in their saved order, the editor pairs it with the disabled remainder.
    static func decodeEnabled(_ raw: String) -> [DashboardCard] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DashboardCard.defaultSelection }

        let ids: [String]
        if let data = trimmed.data(using: .utf8), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            ids = decoded
        } else {
            ids = trimmed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }

        var seen = Set<DashboardCard>()
        var result: [DashboardCard] = []
        for token in ids {
            if let c = DashboardCard(rawValue: token), seen.insert(c).inserted {
                result.append(c)
            }
        }
        // An all-unknown / empty decode shouldn't blank the dashboard, fall back to the default set.
        return result.isEmpty ? DashboardCard.defaultSelection : result
    }
}
