import Foundation

@MainActor
final class APIClient {
    private let urlSession = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    var serverURL: String {
        get { KeychainStore.shared.serverURL }
        set { KeychainStore.shared.serverURL = newValue }
    }

    var secret: String {
        get { KeychainStore.shared.secret }
        set { KeychainStore.shared.secret = newValue }
    }

    var userID: String {
        get { UserDefaults.standard.string(forKey: "cn_user_id") ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "cn_user_id") }
    }

    func fetchHistory() async throws -> [NotificationRecord] {
        let url = try resolve("v1/history", query: ["user_id": userID])
        var req = URLRequest(url: url)
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await urlSession.data(for: req)
        return try decoder.decode([NotificationRecord].self, from: data)
    }

    func registerDevice(token: String) async throws {
        let url = try resolve("v1/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(["user_id": userID, "device_token": token])
        _ = try await urlSession.data(for: req)
    }

    private func resolve(_ path: String, query: [String: String] = [:]) throws -> URL {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              var components = URLComponents(string: "\(trimmed)/\(path)") else {
            throw URLError(.badURL)
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }
}
