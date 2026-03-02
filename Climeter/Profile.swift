import Foundation

struct Profile: Codable, Identifiable {
    let id: UUID
    var name: String
    var autoStartSession: Bool

    init(id: UUID = UUID(), name: String, autoStartSession: Bool = false) {
        self.id = id
        self.name = name
        self.autoStartSession = autoStartSession
    }
}
