import Foundation
import UserNotifications

@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var records: [NotificationRecord] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    let api = APIClient()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    var sessionsSorted: [[NotificationRecord]] {
        Dictionary(grouping: records, by: \.sessionID)
            .values
            .sorted {
                ($0.first?.timestamp ?? .distantPast) > ($1.first?.timestamp ?? .distantPast)
            }
    }

    func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: "cn_records"),
              let loaded = try? decoder.decode([NotificationRecord].self, from: data)
        else { return }
        records = loaded
    }

    func refreshFromServer() async {
        guard !api.serverURL.isEmpty, !api.secret.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            merge(try await api.fetchHistory())
            persist()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func registerDeviceToken(_ token: String) async {
        do {
            try await api.registerDevice(token: token)
        } catch {
            print("[NotificationStore] register: \(error)")
        }
    }

    func ingest(notification: UNNotification) async {
        let info = notification.request.content.userInfo
        merge([NotificationRecord(
            userID: api.userID,
            event: info["event"] as? String ?? "notification",
            sessionID: info["session"] as? String ?? UUID().uuidString,
            cwd: info["cwd"] as? String ?? "",
            title: notification.request.content.title,
            body: notification.request.content.body,
            timestamp: notification.date
        )])
        persist()
    }

    private func merge(_ new: [NotificationRecord]) {
        var seen = Set(records.map(\.id))
        for r in new where !seen.contains(r.id) {
            records.append(r)
            seen.insert(r.id)
        }
        records.sort { $0.timestamp > $1.timestamp }
    }

    private func persist() {
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: "cn_records")
    }
}
