import Foundation

enum CodexUsageMapperError: Error, Equatable {
    case missingWindows
}

enum CodexUsageMapper {
    static func map(_ response: CodexUsageResponse) throws -> UsageData {
        guard let rateLimit = response.rateLimit else {
            throw CodexUsageMapperError.missingWindows
        }

        let windows = [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap(\.self)
        guard !windows.isEmpty else {
            throw CodexUsageMapperError.missingWindows
        }

        let session = window(near: 18_000, in: windows) ?? rateLimit.primaryWindow
        let weekly = window(near: 604_800, in: windows) ?? rateLimit.secondaryWindow

        guard let session, let weekly else {
            throw CodexUsageMapperError.missingWindows
        }

        return UsageData(
            fiveHour: usageWindow(from: session),
            sevenDay: usageWindow(from: weekly)
        )
    }

    private static func window(near target: Int, in windows: [CodexWindowSnapshot]) -> CodexWindowSnapshot? {
        windows.min { lhs, rhs in
            abs(lhs.limitWindowSeconds - target) < abs(rhs.limitWindowSeconds - target)
        }.flatMap { candidate in
            abs(candidate.limitWindowSeconds - target) <= target / 10 ? candidate : nil
        }
    }

    private static func usageWindow(from snapshot: CodexWindowSnapshot) -> UsageWindow {
        UsageWindow(
            utilization: min(100, max(0, Double(snapshot.usedPercent))),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(snapshot.resetAt))
        )
    }
}
