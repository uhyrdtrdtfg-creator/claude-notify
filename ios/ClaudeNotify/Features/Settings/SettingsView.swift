import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: NotificationStore
    @State private var serverURL = ""
    @State private var secret = ""
    @State private var userID = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case ok(Int)
        case fail(String)
        var message: String {
            switch self {
            case .ok(let n): return "Connected — \(n) record(s) in history"
            case .fail(let e): return "Failed: \(e)"
            }
        }
        var isOK: Bool { if case .ok = self { return true } else { return false } }
    }

    var body: some View {
        Form {
            Section("Server") {
                HStack {
                    Text("URL")
                    Spacer()
                    TextField("https://notify.example.com", text: $serverURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Secret")
                    Spacer()
                    SecureField("shared-secret", text: $secret)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("User ID")
                    Spacer()
                    TextField("default", text: $userID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    save()
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Save & Test Connection")
                        Spacer()
                        if isTesting { ProgressView() }
                    }
                }
                .disabled(serverURL.isEmpty || secret.isEmpty || isTesting)

                if let result = testResult {
                    Label(result.message, systemImage: result.isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(result.isOK ? .green : .red)
                }
            }

            Section("Info") {
                LabeledContent("Version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                Link("GitHub", destination: URL(string: "https://github.com/you/claude-notify")!)
                    .font(.body)
            }
        }
        .navigationTitle("Settings")
        .onAppear { load() }
    }

    private func load() {
        serverURL = store.api.serverURL
        secret = store.api.secret
        userID = store.api.userID
    }

    private func save() {
        store.api.serverURL = serverURL
        store.api.secret = secret
        store.api.userID = userID.isEmpty ? "default" : userID
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        do {
            let records = try await store.api.fetchHistory()
            testResult = .ok(records.count)
        } catch {
            testResult = .fail(error.localizedDescription)
        }
    }
}
