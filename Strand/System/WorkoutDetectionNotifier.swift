import Foundation
import UserNotifications

/// Posts a local notification the first time a workout bout is auto-detected, so the user finds out
/// a session was logged without opening the app. Mirrors `IllnessNotifier`'s pattern (request once,
/// post only if authorized, never a second system prompt).
///
/// Re-detection is idempotent by design (`IntelligenceEngine` deletes and re-inserts every "detected"
/// workout in its scored window on every pass, since a bout's start can drift a little as more HR
/// arrives), so naively notifying on every upsert would re-ping the SAME real workout each time its
/// boundary settles. Instead this tracks which bouts have already been notified, keyed by a start
/// timestamp ROUNDED to a coarse bucket so a few minutes of drift still matches the same key.
enum WorkoutDetectionNotifier {
    private static let notifiedKey = "workout.detectionNotified.startBuckets"
    /// Bucket width (seconds) a detected bout's start is rounded to before comparing against the
    /// already-notified set. Wider than any realistic startTs drift between passes, narrower than the
    /// gap between two genuinely separate workouts.
    private static let bucketS = 1800

    /// Ask up front (called once, e.g. when workout auto-detection is first enabled) so the system
    /// dialog appears at a predictable moment rather than on the first detected bout.
    static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func bucket(_ startTs: Int) -> Int { (startTs / bucketS) * bucketS }

    /// Persisted set of start buckets already notified, pruned to the last 30 days so the stored array
    /// never grows unbounded across the lifetime of the app.
    private static func loadNotifiedBuckets(now: Int) -> Set<Int> {
        let raw = (UserDefaults.standard.array(forKey: notifiedKey) as? [Int]) ?? []
        return Set(raw.filter { now - $0 < 30 * 86_400 })
    }

    private static func saveNotifiedBuckets(_ buckets: Set<Int>) {
        UserDefaults.standard.set(Array(buckets), forKey: notifiedKey)
    }

    /// Post a "workout detected" notification for each row in `rows` (a pass's full "detected" set)
    /// that hasn't already been notified, then persist the updated notified set. Safe to call with the
    /// SAME bout across many passes , it fires at most once per real bout regardless of startTs drift.
    /// `durationS`/`avgHr` format the body; no sport name is claimed (auto-detection never classifies
    /// one — see the "detected" placeholder sport in IntelligenceEngine), matching the app's rule of
    /// never fabricating a value it doesn't have.
    static func notifyNewDetections(_ rows: [(startTs: Int, durationS: Double?, avgHr: Int?)]) {
        guard !rows.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let alreadyNotified = loadNotifiedBuckets(now: now)
        let newRows = rows.filter { !alreadyNotified.contains(bucket($0.startTs)) }
        guard !newRows.isEmpty else { return }
        // Mark these buckets notified UP FRONT, before knowing whether the system will actually
        // authorize delivery. Immutable capture below (`newRows`, a `let`) sidesteps mutating captured
        // state inside the completion closure, which the SDK's @Sendable-marked completion forbids, and
        // avoids re-evaluating the same settled bout forever if the user has notifications off.
        saveNotifiedBuckets(alreadyNotified.union(newRows.map { bucket($0.startTs) }))

        // Workout auto-detection is always-on (not a togglable behavior like illness/battery watch,
        // which request authorization from their own Settings toggle), so there's no dedicated "enable"
        // moment to hook a request into , ask here, on the first real detection. Repeat calls are a
        // no-op once the system has already shown its one-time prompt.
        requestAuthorization()
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            for row in newRows {
                let minutes = row.durationS.map { max(1, Int(($0 / 60).rounded())) }
                let body: String
                switch (minutes, row.avgHr) {
                case let (.some(m), .some(hr)):
                    body = String(localized: "\(m) min, avg \(hr) bpm, logged automatically from your strap.")
                case let (.some(m), nil):
                    body = String(localized: "\(m) min, logged automatically from your strap's heart rate and motion.")
                default:
                    body = String(localized: "Logged automatically from your strap's heart rate and motion.")
                }
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Workout detected")
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(identifier: "workout-detected-\(bucket(row.startTs))",
                                                 content: content, trigger: nil))
            }
        }
    }
}
