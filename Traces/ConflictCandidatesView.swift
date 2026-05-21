import SwiftUI
import Foundation

// MARK: - Conflict candidate detail UI
// This file owns the selected-event detail panel and the A/B/C conflict review
// controls. It does not decide which event wins; it only renders candidates and
// asks TracesViewModel to promote the selected candidate when the user clicks the
// explicit final-event button.

/// Sentinel ID used by detail/map views to mean "the current primary event".
/// Suppressed candidates use their own real UUIDs.
let primaryCandidateID = "__primary__"

/// Center-bottom detail view for the currently selected event.
///
/// Controlled view area:
/// - event title and metadata
/// - conflict candidate panel
/// - final-event replacement button
/// - raw generated description text
struct EventDetailView: View {
    let event: ICSEvent
    @Binding var selectedConflictCandidateID: String?
    let onPromoteConflictCandidate: () -> Void

    /// Promotion is only valid when B/C/etc is selected. Selecting A means the
    /// existing final event is already active, so there is nothing to promote.
    private var canPromote: Bool {
        guard let selectedConflictCandidateID else {
            return false
        }

        return event.suppressedCandidates.contains { $0.id == selectedConflictCandidateID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.summary)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)

                // Shows A/B/C only when TimelineProcessor found impossible or
                // highly overlapping location candidates.
                if !event.suppressedCandidates.isEmpty {
                    ConflictCandidatesView(
                        event: event,
                        selectedConflictCandidateID: $selectedConflictCandidateID,
                        onPromoteConflictCandidate: onPromoteConflictCandidate
                    )
                }

                // Main event metadata. These are the values that will be used by
                // ICS export unless the user promotes another candidate first.
                VStack(alignment: .leading, spacing: 8) {
                    Label(dateRange(event), systemImage: "calendar")

                    if !event.location.isEmpty {
                        Label(event.location, systemImage: "mappin.and.ellipse")
                            .textSelection(.enabled)
                    }

                    if let lat = event.lat, let lon = event.lon {
                        Label(String(format: "%.6f, %.6f", lat, lon), systemImage: "location")
                            .textSelection(.enabled)
                    }

                    if !event.url.isEmpty, let url = URL(string: event.url) {
                        Link(event.url, destination: url)
                    }
                }

                // Duplicate promotion button outside the warning card so the
                // action remains visible even after scrolling through details.
                if canPromote {
                    Button {
                        onPromoteConflictCandidate()
                    } label: {
                        Label("Use selected candidate as final event", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if !event.description.isEmpty {
                    Divider()

                    Text(event.description)
                        .textSelection(.enabled)
                        .font(.body)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Warning/review card for overlapping location candidates.
///
/// A is the current final event. B/C/etc are suppressed candidates that occurred
/// in the same or overlapping time window and may be more correct.
struct ConflictCandidatesView: View {
    let event: ICSEvent
    @Binding var selectedConflictCandidateID: String?
    let onPromoteConflictCandidate: () -> Void

    private var effectiveSelectedCandidateID: String {
        selectedConflictCandidateID ?? primaryCandidateID
    }

    private var canPromote: Bool {
        guard let selectedConflictCandidateID else {
            return false
        }

        return event.suppressedCandidates.contains { $0.id == selectedConflictCandidateID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Detected \(event.suppressedCandidates.count + 1) overlapping location candidates",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text("点击 A/B/C 可以在地图上高亮对应地点。A 是当前最终事件，B/C 是同一时间段被折叠的冲突候选地点。选择 B/C 后可以替换最终生成的事件。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                // A is not stored in suppressedCandidates. It represents the
                // current ICSEvent itself.
                CandidateRow(
                    label: "A",
                    title: event.summary,
                    subtitle: event.location,
                    distance: nil,
                    isPrimary: true,
                    isSelected: effectiveSelectedCandidateID == primaryCandidateID
                ) {
                    selectedConflictCandidateID = nil
                }

                // B/C/etc are the alternate places kept for user review.
                ForEach(Array(event.suppressedCandidates.enumerated()), id: \.element.id) { index, candidate in
                    CandidateRow(
                        label: candidateLabel(index + 1),
                        title: candidate.title,
                        subtitle: candidateSubtitle(candidate),
                        distance: candidate.distanceMetersFromPrimary,
                        isPrimary: false,
                        isSelected: effectiveSelectedCandidateID == candidate.id
                    ) {
                        selectedConflictCandidateID = candidate.id
                    }
                }
            }

            if canPromote {
                HStack {
                    Spacer()

                    Button {
                        onPromoteConflictCandidate()
                    } label: {
                        Label("Use selected as final event", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func candidateLabel(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard index < letters.count else {
            return "\(index + 1)"
        }
        return String(letters[index])
    }

    private func candidateSubtitle(_ candidate: SuppressedCandidate) -> String {
        var parts: [String] = []

        if !candidate.placeID.isEmpty {
            parts.append("Place ID: \(candidate.placeID)")
        }

        if let lat = candidate.lat, let lon = candidate.lon {
            parts.append(String(format: "%.6f, %.6f", lat, lon))
        }

        return parts.joined(separator: " · ")
    }
}

/// One clickable A/B/C row. The row updates preview selection only; it does not
/// mutate the final generated event by itself.
struct CandidateRow: View {
    let label: String
    let title: String
    let subtitle: String
    let distance: Double?
    let isPrimary: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.caption.bold())
                    .frame(width: 24, height: 24)
                    .background(markerBackground, in: Circle())
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.bold())
                            .lineLimit(1)

                        if let distance {
                            Text("\(Int(distance.rounded()))m")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }

                        if isSelected {
                            Text("Selected")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var markerBackground: Color {
        if isSelected {
            return .blue
        }

        return isPrimary ? .accentColor : .orange
    }
}
