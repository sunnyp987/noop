import Foundation

// MARK: - WHOOP Cloud API v2 — response models
//
// Mirrors only the fields the comparison engine actually reads. Field names match
// developer.whoop.com/api exactly (snake_case JSON via CodingKeys) as of 2026.

enum WhoopCloud {

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    struct Page<Record: Decodable>: Decodable {
        let records: [Record]
        let nextToken: String?

        enum CodingKeys: String, CodingKey {
            case records
            case nextToken = "next_token"
        }
    }

    struct CycleScore: Decodable {
        let strain: Double?
        let kilojoule: Double?
        let averageHeartRate: Int?
        let maxHeartRate: Int?

        enum CodingKeys: String, CodingKey {
            case strain, kilojoule
            case averageHeartRate = "average_heart_rate"
            case maxHeartRate = "max_heart_rate"
        }
    }

    struct Cycle: Decodable {
        let id: Int
        let start: String
        let end: String?
        let scoreState: String
        let score: CycleScore?

        enum CodingKeys: String, CodingKey {
            case id, start, end
            case scoreState = "score_state"
            case score
        }
    }

    struct RecoveryScore: Decodable {
        let userCalibrating: Bool?
        let recoveryScore: Double?
        let restingHeartRate: Double?
        let hrvRmssdMilli: Double?
        let spo2Percentage: Double?
        let skinTempCelsius: Double?

        enum CodingKeys: String, CodingKey {
            case userCalibrating = "user_calibrating"
            case recoveryScore = "recovery_score"
            case restingHeartRate = "resting_heart_rate"
            case hrvRmssdMilli = "hrv_rmssd_milli"
            case spo2Percentage = "spo2_percentage"
            case skinTempCelsius = "skin_temp_celsius"
        }
    }

    struct Recovery: Decodable {
        let cycleId: Int
        let scoreState: String
        let score: RecoveryScore?

        enum CodingKeys: String, CodingKey {
            case cycleId = "cycle_id"
            case scoreState = "score_state"
            case score
        }
    }

    struct SleepStageSummary: Decodable {
        let totalInBedTimeMilli: Double?
        let totalAwakeTimeMilli: Double?
        let totalLightSleepTimeMilli: Double?
        let totalSlowWaveSleepTimeMilli: Double?
        let totalRemSleepTimeMilli: Double?
        let disturbanceCount: Int?

        enum CodingKeys: String, CodingKey {
            case totalInBedTimeMilli = "total_in_bed_time_milli"
            case totalAwakeTimeMilli = "total_awake_time_milli"
            case totalLightSleepTimeMilli = "total_light_sleep_time_milli"
            case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli"
            case totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
            case disturbanceCount = "disturbance_count"
        }
    }

    struct SleepNeeded: Decodable {
        let baselineMilli: Double?
        let needFromSleepDebtMilli: Double?
        let needFromRecentStrainMilli: Double?
        let needFromRecentNapMilli: Double?

        enum CodingKeys: String, CodingKey {
            case baselineMilli = "baseline_milli"
            case needFromSleepDebtMilli = "need_from_sleep_debt_milli"
            case needFromRecentStrainMilli = "need_from_recent_strain_milli"
            case needFromRecentNapMilli = "need_from_recent_nap_milli"
        }
    }

    struct SleepScore: Decodable {
        let respiratoryRate: Double?
        let sleepPerformancePercentage: Double?
        let sleepConsistencyPercentage: Double?
        let sleepEfficiencyPercentage: Double?
        let stageSummary: SleepStageSummary?
        let sleepNeeded: SleepNeeded?

        enum CodingKeys: String, CodingKey {
            case respiratoryRate = "respiratory_rate"
            case sleepPerformancePercentage = "sleep_performance_percentage"
            case sleepConsistencyPercentage = "sleep_consistency_percentage"
            case sleepEfficiencyPercentage = "sleep_efficiency_percentage"
            case stageSummary = "stage_summary"
            case sleepNeeded = "sleep_needed"
        }
    }

    struct SleepActivity: Decodable {
        // WHOOP v2 uses a UUID string here (unlike Cycle/Recovery's integer ids) — decoding this as
        // Int would silently fail every sleep fetch.
        let id: String
        let start: String
        let end: String
        let nap: Bool
        let scoreState: String
        let score: SleepScore?

        enum CodingKeys: String, CodingKey {
            case id, start, end, nap
            case scoreState = "score_state"
            case score
        }
    }
}
