import SwiftUI
import Foundation

struct EventRow: View {
    let event: ICSEvent
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(event.summary)
                    .font(.headline)
                    .lineLimit(compact ? 2 : 1)
                    .truncationMode(.tail)

                if !event.suppressedCandidates.isEmpty {
                    Text("+\(event.suppressedCandidates.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.22), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            Text(dateRange(event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !compact && !event.location.isEmpty {
                Text(event.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 5)
    }
}

func dateRange(_ event: ICSEvent) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    switch (event.start, event.end) {
    case let (start?, end?):
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    case let (start?, nil):
        return formatter.string(from: start)
    default:
        return "No time"
    }
}
