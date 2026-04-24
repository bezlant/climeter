import Foundation

struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: CodexRateLimitDetails?
    let credits: CodexCreditDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

struct CodexRateLimitDetails: Decodable, Equatable {
    let primaryWindow: CodexWindowSnapshot?
    let secondaryWindow: CodexWindowSnapshot?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct CodexWindowSnapshot: Decodable, Equatable {
    let usedPercent: Int
    let resetAt: Int
    let limitWindowSeconds: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }
}

struct CodexCreditDetails: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
