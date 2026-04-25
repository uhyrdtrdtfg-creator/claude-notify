import Foundation

struct NotificationRecord: Codable, Identifiable, Hashable {
    var id: String { "\(sessionID)|\(timestamp.timeIntervalSinceReferenceDate)" }

    let userID: String
    let event: String
    let sessionID: String
    let cwd: String
    let title: String
    let body: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case event
        case sessionID = "session_id"
        case cwd, title, body, timestamp
    }

    init(userID: String, event: String, sessionID: String, cwd: String,
         title: String, body: String, timestamp: Date) {
        self.userID = userID
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title
        self.body = body
        self.timestamp = timestamp
    }

    var projectName: String {
        guard !cwd.isEmpty else { return "Claude Code" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var eventLabel: String {
        switch event {
        case "stop": return "Done"
        case "subagent_stop": return "Subagent Done"
        case "notification": return "Notice"
        case "session_end": return "Ended"
        default: return event.capitalized
        }
    }

    var eventSystemImage: String {
        switch event {
        case "stop", "subagent_stop": return "checkmark.circle"
        case "notification": return "bell"
        case "session_end": return "xmark.circle"
        default: return "dot.radiowaves.right"
        }
    }
}
