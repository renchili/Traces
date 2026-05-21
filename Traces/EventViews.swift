import SwiftUI
import Foundation
import MapKit

private let primaryCandidateID = "__primary__"

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

struct EventDetailView: View {
    let event: ICSEvent
    @Binding var selectedConflictCandidateID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.summary)
                    .font(.largeTitle.bold())
                    .textSelection(.enabled)

                if !event.suppressedCandidates.isEmpty {
                    ConflictWarningView(
                        event: event,
                        selectedConflictCandidateID: $selectedConflictCandidateID
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

struct ConflictWarningView: View {
    let event: ICSEvent
    @Binding var selectedConflictCandidateID: String?

    private var effectiveSelectedCandidateID: String {
        selectedConflictCandidateID ?? primaryCandidateID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "Detected \(event.suppressedCandidates.count + 1) overlapping location candidates",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.headline)
            .foregroundStyle(.orange)

            Text("点击 A/B/C 可以在地图上高亮对应地点。A 是当前保留的主地点，B/C 是同一时间段被折叠的冲突候选地点。")
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

struct EventMapPanel: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?
    @Binding var selectedConflictCandidateID: String?

    private var selectedEvent: ICSEvent? {
        events.first { $0.id == selectedEventID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Map")
                    .font(.headline)

                Spacer()

                if let selectedEvent, !selectedEvent.suppressedCandidates.isEmpty {
                    Text("\(selectedEvent.suppressedCandidates.count + 1) candidates · click A/B/C")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } else if let selectedEvent, let lat = selectedEvent.lat, let lon = selectedEvent.lon {
                    Text(String(format: "%.5f, %.5f", lat, lon))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No coordinate")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            EventMapView(
                events: events,
                selectedEventID: selectedEventID,
                selectedConflictCandidateID: $selectedConflictCandidateID
            )
        }
        .background(.background)
    }
}

struct EventMapView: NSViewRepresentable {
    let events: [ICSEvent]
    let selectedEventID: String?
    @Binding var selectedConflictCandidateID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedConflictCandidateID: $selectedConflictCandidateID)
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsZoomControls = true
        map.showsCompass = true
        return map
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.selectedConflictCandidateID = $selectedConflictCandidateID

        nsView.removeAnnotations(nsView.annotations)
        nsView.removeOverlays(nsView.overlays)

        guard let selectedEvent = events.first(where: { $0.id == selectedEventID }) else {
            let annotations = allEventAnnotations()
            nsView.addAnnotations(annotations)

            if !annotations.isEmpty {
                nsView.showAnnotations(annotations, animated: false)
            }

            return
        }

        let annotations = selectedEventAnnotations(for: selectedEvent)
        let overlays = conflictOverlays(for: selectedEvent)

        nsView.addAnnotations(annotations)
        nsView.addOverlays(overlays)

        let targetCandidateID = selectedConflictCandidateID ?? primaryCandidateID

        if let selectedAnnotation = annotations.first(where: { $0.candidateID == targetCandidateID }) {
            nsView.selectAnnotation(selectedAnnotation, animated: true)

            if selectedEvent.suppressedCandidates.isEmpty {
                nsView.setRegion(
                    MKCoordinateRegion(
                        center: selectedAnnotation.coordinate,
                        latitudinalMeters: 700,
                        longitudinalMeters: 700
                    ),
                    animated: true
                )
            } else {
                nsView.showAnnotations(annotations, animated: true)
            }
        } else if !annotations.isEmpty {
            nsView.showAnnotations(annotations, animated: true)
        }
    }

    private func allEventAnnotations() -> [EventAnnotation] {
        events.compactMap { event in
            guard let lat = event.lat, let lon = event.lon else {
                return nil
            }

            return EventAnnotation(
                eventID: event.id,
                candidateID: primaryCandidateID,
                label: "",
                title: event.summary,
                subtitle: event.location,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private func selectedEventAnnotations(for event: ICSEvent) -> [EventAnnotation] {
        let currentSelection = selectedConflictCandidateID ?? primaryCandidateID
        var annotations: [EventAnnotation] = []

        if let lat = event.lat, let lon = event.lon {
            annotations.append(
                EventAnnotation(
                    eventID: event.id,
                    candidateID: primaryCandidateID,
                    label: currentSelection == primaryCandidateID ? "A*" : "A",
                    title: "A · \(event.summary)",
                    subtitle: event.location,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            )
        }

        for (index, candidate) in event.suppressedCandidates.enumerated() {
            guard let lat = candidate.lat, let lon = candidate.lon else {
                continue
            }

            let label = candidateLabel(index + 1)
            let selectedLabel = currentSelection == candidate.id ? "\(label)*" : label

            annotations.append(
                EventAnnotation(
                    eventID: event.id,
                    candidateID: candidate.id,
                    label: selectedLabel,
                    title: "\(label) · \(candidate.title)",
                    subtitle: distanceSubtitle(candidate),
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
            )
        }

        return annotations
    }

    private func conflictOverlays(for event: ICSEvent) -> [ConflictPolyline] {
        guard let lat = event.lat, let lon = event.lon else {
            return []
        }

        let primary = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let currentSelection = selectedConflictCandidateID ?? primaryCandidateID

        return event.suppressedCandidates.compactMap { candidate in
            guard let candidateLat = candidate.lat, let candidateLon = candidate.lon else {
                return nil
            }

            let points = [
                primary,
                CLLocationCoordinate2D(latitude: candidateLat, longitude: candidateLon)
            ]

            return ConflictPolyline(
                coordinates: points,
                candidateID: candidate.id,
                isSelected: currentSelection == candidate.id
            )
        }
    }

    private func candidateLabel(_ index: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard index < letters.count else {
            return "\(index + 1)"
        }
        return String(letters[index])
    }

    private func distanceSubtitle(_ candidate: SuppressedCandidate) -> String {
        if let distance = candidate.distanceMetersFromPrimary {
            return "\(Int(distance.rounded()))m from A"
        }

        return "Overlapping candidate"
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var selectedConflictCandidateID: Binding<String?>

        init(selectedConflictCandidateID: Binding<String?>) {
            self.selectedConflictCandidateID = selectedConflictCandidateID
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? EventAnnotation else {
                return
            }

            if annotation.candidateID == primaryCandidateID {
                selectedConflictCandidateID.wrappedValue = nil
            } else {
                selectedConflictCandidateID.wrappedValue = annotation.candidateID
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let overlay = overlay as? ConflictPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.strokeColor = overlay.isSelected
                ? NSColor.systemBlue
                : NSColor.systemOrange.withAlphaComponent(0.65)
            renderer.lineWidth = overlay.isSelected ? 4 : 2
            renderer.lineDashPattern = overlay.isSelected ? nil : [6, 4]

            return renderer
        }
    }
}

final class EventAnnotation: NSObject, MKAnnotation {
    let eventID: String
    let candidateID: String
    let label: String
    let coordinate: CLLocationCoordinate2D

    private let annotationTitle: String?
    private let annotationSubtitle: String?

    var title: String? {
        label.isEmpty ? annotationTitle : "\(label) · \(annotationTitle ?? "")"
    }

    var subtitle: String? {
        annotationSubtitle
    }

    init(
        eventID: String,
        candidateID: String,
        label: String,
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.eventID = eventID
        self.candidateID = candidateID
        self.label = label
        self.annotationTitle = title
        self.annotationSubtitle = subtitle
        self.coordinate = coordinate
        super.init()
    }
}

final class ConflictPolyline: MKPolyline {
    let candidateID: String
    let isSelected: Bool

    init(
        coordinates coords: [CLLocationCoordinate2D],
        candidateID: String,
        isSelected: Bool
    ) {
        self.candidateID = candidateID
        self.isSelected = isSelected

        var mutableCoords = coords
        super.init(coordinates: &mutableCoords, count: mutableCoords.count)
    }
}

struct TimelineWaterfallView: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?

    private var datedEvents: [ICSEvent] {
        events
            .filter { $0.start != nil && $0.end != nil }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }

    private var dayStart: Date? {
        guard let first = datedEvents.first?.start else { return nil }
        return Calendar.current.startOfDay(for: first)
    }

    private var dayEnd: Date? {
        guard let last = datedEvents.compactMap(\.end).max() else { return nil }
        return Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: last)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(220, proxy.size.width)
            let widthBucket = Int(width.rounded())

            VStack(spacing: 0) {
                HStack {
                    Text("Timeline")
                        .font(.headline)

                    Spacer()

                    Text("\(datedEvents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                if datedEvents.isEmpty {
                    ContentUnavailableView(
                        "No timed events",
                        systemImage: "timeline.selection",
                        description: Text("Open Timeline JSON or ICS with event times.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        TimelineCanvas(
                            events: datedEvents,
                            selectedEventID: $selectedEventID,
                            dayStart: dayStart,
                            dayEnd: dayEnd,
                            availableWidth: width - 24
                        )
                        .padding(12)
                        .id(widthBucket)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.background)
        }
    }
}

struct TimelineCanvas: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?
    let dayStart: Date?
    let dayEnd: Date?
    let availableWidth: CGFloat

    private let hourHeight: CGFloat = 52
    private let labelWidth: CGFloat = 46
    private let columnGap: CGFloat = 6
    private let contentLeftPadding: CGFloat = 8
    private let contentRightPadding: CGFloat = 8

    private struct LayoutItem: Identifiable {
        let id: String
        let event: ICSEvent
        let column: Int
        let totalColumns: Int
    }

    private var totalHours: CGFloat {
        guard let dayStart, let dayEnd else { return 24 }
        return max(24, CGFloat(dayEnd.timeIntervalSince(dayStart) / 3600.0))
    }

    private var canvasHeight: CGFloat {
        totalHours * hourHeight
    }

    private var canvasWidth: CGFloat {
        max(220, availableWidth)
    }

    var body: some View {
        let layoutItems = makeLayoutItems()

        ZStack(alignment: .topLeading) {
            hourGrid(totalWidth: canvasWidth)

            ForEach(layoutItems, id: \.id) { item in
                if let rect = rectForEvent(item, totalWidth: canvasWidth) {
                    TimelineEventBlock(
                        event: item.event,
                        isSelected: item.event.id == selectedEventID,
                        compact: rect.width < 110
                    )
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture {
                        selectedEventID = item.event.id
                    }
                    .zIndex(item.event.id == selectedEventID ? 10 : 1)
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight, alignment: .topLeading)
    }

    private func hourGrid(totalWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...Int(totalHours), id: \.self) { hour in
                let y = CGFloat(hour) * hourHeight

                Path { path in
                    path.move(to: CGPoint(x: labelWidth, y: y))
                    path.addLine(to: CGPoint(x: totalWidth, y: y))
                }
                .stroke(.quaternary, lineWidth: 1)

                Text(hourLabel(hour))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth - 6, alignment: .trailing)
                    .position(x: (labelWidth - 6) / 2, y: y + 7)
            }
        }
    }

    private func makeLayoutItems() -> [LayoutItem] {
        let sorted = events.sorted {
            let lhs = $0.start ?? .distantPast
            let rhs = $1.start ?? .distantPast

            if lhs == rhs {
                return ($0.end ?? .distantPast) < ($1.end ?? .distantPast)
            }

            return lhs < rhs
        }

        var groups: [[ICSEvent]] = []
        var currentGroup: [ICSEvent] = []
        var currentGroupMaxEnd: Date?

        for event in sorted {
            guard let start = event.start, let end = event.end else {
                continue
            }

            if let groupEnd = currentGroupMaxEnd, start < groupEnd {
                currentGroup.append(event)

                if end > groupEnd {
                    currentGroupMaxEnd = end
                }
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }

                currentGroup = [event]
                currentGroupMaxEnd = end
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        var result: [LayoutItem] = []

        for group in groups {
            result.append(contentsOf: layoutGroup(group))
        }

        return result
    }

    private func layoutGroup(_ group: [ICSEvent]) -> [LayoutItem] {
        let sorted = group.sorted {
            let lhs = $0.start ?? .distantPast
            let rhs = $1.start ?? .distantPast

            if lhs == rhs {
                return ($0.end ?? .distantPast) < ($1.end ?? .distantPast)
            }

            return lhs < rhs
        }

        var columnEndDates: [Date] = []
        var temporary: [(event: ICSEvent, column: Int)] = []

        for event in sorted {
            guard let start = event.start, let end = event.end else {
                continue
            }

            var assignedColumn: Int?

            for index in columnEndDates.indices {
                if start >= columnEndDates[index] {
                    assignedColumn = index
                    columnEndDates[index] = end
                    break
                }
            }

            if assignedColumn == nil {
                columnEndDates.append(end)
                assignedColumn = columnEndDates.count - 1
            }

            temporary.append((event: event, column: assignedColumn ?? 0))
        }

        let totalColumns = max(1, columnEndDates.count)

        return temporary.map {
            LayoutItem(
                id: $0.event.id,
                event: $0.event,
                column: $0.column,
                totalColumns: totalColumns
            )
        }
    }

    private func rectForEvent(_ item: LayoutItem, totalWidth: CGFloat) -> CGRect? {
        guard
            let dayStart,
            let start = item.event.start,
            let end = item.event.end
        else {
            return nil
        }

        let startHours = max(0, start.timeIntervalSince(dayStart) / 3600.0)
        let endHours = max(startHours + 0.15, end.timeIntervalSince(dayStart) / 3600.0)

        let y = CGFloat(startHours) * hourHeight
        let height = max(30, CGFloat(endHours - startHours) * hourHeight)

        let usableWidth = max(
            90,
            totalWidth - labelWidth - contentLeftPadding - contentRightPadding
        )

        let totalGap = CGFloat(max(0, item.totalColumns - 1)) * columnGap
        let columnWidth = max(
            56,
            (usableWidth - totalGap) / CGFloat(item.totalColumns)
        )

        let x =
            labelWidth
            + contentLeftPadding
            + CGFloat(item.column) * (columnWidth + columnGap)

        return CGRect(
            x: x,
            y: y,
            width: columnWidth,
            height: height
        )
    }

    private func hourLabel(_ hourOffset: Int) -> String {
        guard let dayStart else {
            return "\(hourOffset):00"
        }

        let date = Calendar.current.date(byAdding: .hour, value: hourOffset, to: dayStart) ?? dayStart
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

struct TimelineEventBlock: View {
    let event: ICSEvent
    let isSelected: Bool
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(event.summary)
                    .font(.caption.bold())
                    .lineLimit(compact ? 1 : 2)
                    .truncationMode(.tail)

                if !event.suppressedCandidates.isEmpty {
                    Text("+\(event.suppressedCandidates.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                }
            }

            Text(shortTimeRange(event))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(compact ? 5 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.20),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .clipped()
    }

    private func shortTimeRange(_ event: ICSEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let start = event.start else {
            return "No time"
        }

        if let end = event.end {
            return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
        }

        return formatter.string(from: start)
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
