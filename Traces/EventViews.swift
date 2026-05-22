import SwiftUI
import Foundation

// MARK: - Shared event list views
// Owns only the reusable event row and shared date range formatter.
// Map, timeline, and conflict-detail rendering live in separate files.

/// One event row in the left event list.
/// Shows title, conflict count, time range, and optional location preview.
struct EventRow: View {
    let event: ICSEvent
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: event.suppressedCandidates.isEmpty ? "mappin.and.ellipse" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(event.suppressedCandidates.isEmpty ? Color.accentColor : TracesTheme.warning)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(event.summary)
                            .font(.system(size: compact ? 13 : 14, weight: .semibold))
                            .lineLimit(compact ? 2 : 1)
                            .truncationMode(.tail)

                        if !event.suppressedCandidates.isEmpty {
                            TracesBadge(
                                "+\(event.suppressedCandidates.count)",
                                systemImage: "point.3.connected.trianglepath.dotted",
                                tint: TracesTheme.warning
                            )
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(dateRange(event))
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !compact && !event.location.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "location")
                                .font(.caption2)
                            Text(event.location)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
    }
}

/// Formats event dates for display in SwiftUI views.
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
