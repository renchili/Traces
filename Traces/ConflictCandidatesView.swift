import SwiftUI
import Foundation

let primaryCandidateID = "__primary__"

struct EventDetailView: View {
    let event: ICSEvent
    @Binding var selectedConflictCandidateID: String?
    let onPromoteConflictCandidate: () -> Void

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

                if !event.suppressedCandidates.isEmpty {
                    ConflictCandidatesView(
                        event: event,
                        selectedConflictCandidateID: $selectedConflictCandidateID,
                        onPromoteConflictCandidate: onPromoteConflictCandidate
                    )
                }

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
