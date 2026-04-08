import Foundation

struct Credential {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var subscriptionType: String?
    var rateLimitTier: String?
    var accountUUID: String?

    var isExpired: Bool {
        expiresAt < Date.now.addingTimeInterval(5 * 60)
    }

    init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String,
              let refreshToken = oauth["refreshToken"] as? String else {
            return nil
        }

        self.accessToken = accessToken
        self.refreshToken = refreshToken

        if let expiresAt = oauth["expiresAt"] as? TimeInterval {
            self.expiresAt = Date(timeIntervalSince1970: expiresAt / 1000)
        } else {
            self.expiresAt = .distantFuture
        }

        self.subscriptionType = oauth["subscriptionType"] as? String
        self.rateLimitTier = oauth["rateLimitTier"] as? String
        self.accountUUID = oauth["accountUUID"] as? String
    }

    func toJSONString() -> String {
        var oauth: [String: Any] = [
            "accessToken": accessToken,
            "refreshToken": refreshToken,
            "expiresAt": Int(expiresAt.timeIntervalSince1970 * 1000)
        ]
        if let subscriptionType { oauth["subscriptionType"] = subscriptionType }
        if let rateLimitTier { oauth["rateLimitTier"] = rateLimitTier }
        if let accountUUID { oauth["accountUUID"] = accountUUID }

        let wrapper: [String: Any] = ["claudeAiOauth": oauth]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
