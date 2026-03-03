import Foundation

struct UsageWindow: Codable {
    let utilization: Double
    let resetsAt: Date

    private enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageData: Codable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}
