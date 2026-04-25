import SwiftUI

// Root view — aliased as ContentView so ClaudeNotifyApp.swift needs no change.
typealias ContentView = InboxView

struct InboxView: View {
    @EnvironmentObject var store: NotificationStore

    var body: some View {
        NavigationStack {
            Group {
                if store.records.isEmpty && !store.isLoading {
                    EmptyInboxView()
                } else {
                    sessionList
                }
            }
            .navigationTitle("Claude Notify")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await store.refreshFromServer() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await store.refreshFromServer()
            }
            .alert("Error", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var sessionList: some View {
        List(store.sessionsSorted, id: \.first?.sessionID) { session in
            NavigationLink(destination: SessionDetailView(records: session)) {
                SessionRowView(records: session)
            }
        }
        .listStyle(.plain)
    }
}

private struct SessionRowView: View {
    let records: [NotificationRecord]
    private var latest: NotificationRecord? { records.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(latest?.projectName ?? "Claude Code")
                    .font(.headline)
                Spacer()
                Text(latest?.timestamp ?? Date(), style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(latest?.body ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                Label(latest?.eventLabel ?? "", systemImage: latest?.eventSystemImage ?? "bell")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.teal.opacity(0.12), in: Capsule())
                if records.count > 1 {
                    Text("\(records.count) events")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct EmptyInboxView: View {
    var body: some View {
        ContentUnavailableView(
            "No Notifications Yet",
            systemImage: "bell.slash",
            description: Text("Configure the server URL in Settings, then run Claude Code to start receiving notifications.")
        )
    }
}
