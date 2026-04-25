import SwiftUI

struct SessionDetailView: View {
    let records: [NotificationRecord]

    private var sorted: [NotificationRecord] { records.sorted { $0.timestamp > $1.timestamp } }

    var body: some View {
        List(sorted) { record in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(record.eventLabel, systemImage: record.eventSystemImage)
                        .font(.caption)
                        .foregroundStyle(.teal)
                    Spacer()
                    Text(record.timestamp, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.body)
                    .font(.body)
                    .textSelection(.enabled)
                if !record.cwd.isEmpty {
                    Text(record.cwd)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle(records.first?.projectName ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
    }
}
