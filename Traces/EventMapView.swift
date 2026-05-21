import SwiftUI
import MapKit

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
        context.coordinator.isApplyingSwiftUIUpdate = true

        nsView.removeAnnotations(nsView.annotations)
        nsView.removeOverlays(nsView.overlays)

        guard let selectedEvent = events.first(where: { $0.id == selectedEventID }) else {
            let annotations = allEventAnnotations()
            nsView.addAnnotations(annotations)

            if !annotations.isEmpty {
                nsView.showAnnotations(annotations, animated: false)
            }

            DispatchQueue.main.async {
                context.coordinator.isApplyingSwiftUIUpdate = false
            }

            return
        }

        let annotations = selectedEventAnnotations(for: selectedEvent)
        let overlays = conflictOverlays(for: selectedEvent)

        nsView.addAnnotations(annotations)
        nsView.addOverlays(overlays)

        let targetCandidateID = selectedConflictCandidateID ?? primaryCandidateID

        if let selectedAnnotation = annotations.first(where: { $0.candidateID == targetCandidateID }) {
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

            DispatchQueue.main.async {
                context.coordinator.isApplyingSwiftUIUpdate = true
                nsView.selectAnnotation(selectedAnnotation, animated: true)

                DispatchQueue.main.async {
                    context.coordinator.isApplyingSwiftUIUpdate = false
                }
            }
        } else {
            if !annotations.isEmpty {
                nsView.showAnnotations(annotations, animated: true)
            }

            DispatchQueue.main.async {
                context.coordinator.isApplyingSwiftUIUpdate = false
            }
        }
    }

    private func allEventAnnotations() -> [TracesMapAnnotation] {
        events.compactMap { event in
            guard let lat = event.lat, let lon = event.lon else {
                return nil
            }

            return TracesMapAnnotation(
                eventID: event.id,
                candidateID: primaryCandidateID,
                label: "",
                title: event.summary,
                subtitle: event.location,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            )
        }
    }

    private func selectedEventAnnotations(for event: ICSEvent) -> [TracesMapAnnotation] {
        let currentSelection = selectedConflictCandidateID ?? primaryCandidateID
        var annotations: [TracesMapAnnotation] = []

        if let lat = event.lat, let lon = event.lon {
            annotations.append(
                TracesMapAnnotation(
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
                TracesMapAnnotation(
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

    private func conflictOverlays(for event: ICSEvent) -> [MKPolyline] {
        guard let lat = event.lat, let lon = event.lon else {
            return []
        }

        let primary = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let currentSelection = selectedConflictCandidateID ?? primaryCandidateID

        return event.suppressedCandidates.compactMap { candidate in
            guard let candidateLat = candidate.lat, let candidateLon = candidate.lon else {
                return nil
            }

            var points = [
                primary,
                CLLocationCoordinate2D(latitude: candidateLat, longitude: candidateLon)
            ]

            let line = MKPolyline(coordinates: &points, count: points.count)
            line.title = currentSelection == candidate.id ? "selected" : "normal"
            return line
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
        var isApplyingSwiftUIUpdate = false

        init(selectedConflictCandidateID: Binding<String?>) {
            self.selectedConflictCandidateID = selectedConflictCandidateID
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isApplyingSwiftUIUpdate else {
                return
            }

            guard let annotation = view.annotation as? TracesMapAnnotation else {
                return
            }

            DispatchQueue.main.async {
                if annotation.candidateID == primaryCandidateID {
                    self.selectedConflictCandidateID.wrappedValue = nil
                } else {
                    self.selectedConflictCandidateID.wrappedValue = annotation.candidateID
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            let isSelected = polyline.title == "selected"

            renderer.strokeColor = isSelected
                ? NSColor.systemBlue
                : NSColor.systemOrange.withAlphaComponent(0.65)
            renderer.lineWidth = isSelected ? 4 : 2
            renderer.lineDashPattern = isSelected ? nil : [6, 4]

            return renderer
        }
    }
}

final class TracesMapAnnotation: NSObject, MKAnnotation {
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
