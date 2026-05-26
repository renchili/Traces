import SwiftUI
import MapKit

// MARK: - Map preview views
// This file is the only place that should directly use MapKit. It renders the
// center-top map panel, maps selected events/candidates to annotations, draws
// conflict distance lines, and bridges MapKit selection back into SwiftUI state.

/// Header/container for the map area in the center split panel.
struct EventMapPanel: View {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?
    @Binding var selectedConflictCandidateID: String?
    let selectedPlaceFilterKey: String?
    let selectedPlaceFilterTitle: String?
    let onSelectPlace: (String, String, String) -> Void
    let onClearPlaceFilter: () -> Void

    private var selectedEvent: ICSEvent? {
        events.first { $0.id == selectedEventID }
    }

    private var eventCountWithCoordinates: Int {
        events.filter { $0.lat != nil && $0.lon != nil }.count
    }

    private var subtitle: String {
        if let selectedPlaceFilterTitle {
            return "Place filter · \(selectedPlaceFilterTitle)"
        }

        if let selectedEvent, !selectedEvent.suppressedCandidates.isEmpty {
            return "\(selectedEvent.suppressedCandidates.count + 1) candidates · choose A/B/C on map"
        }

        if let selectedEvent, let lat = selectedEvent.lat, let lon = selectedEvent.lon {
            return String(format: "Selected · %.5f, %.5f", lat, lon)
        }

        return "All events · \(eventCountWithCoordinates) with coordinates"
    }

    var body: some View {
        TracesPanel(
            title: "Map",
            subtitle: subtitle,
            systemImage: selectedPlaceFilterKey == nil ? "map" : "line.3.horizontal.decrease.circle",
            trailing: AnyView(
                HStack(spacing: 8) {
                    if selectedPlaceFilterKey != nil {
                        Button {
                            onClearPlaceFilter()
                        } label: {
                            Label("Clear Place", systemImage: "xmark.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(TracesIconButtonStyle())
                    }

                    Button {
                        selectedEventID = nil
                        selectedConflictCandidateID = nil
                    } label: {
                        Label("Show All", systemImage: "map")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(TracesIconButtonStyle())
                    .disabled(selectedEventID == nil && selectedPlaceFilterKey == nil)
                }
            )
        ) {
            EventMapView(
                events: events,
                selectedEventID: $selectedEventID,
                selectedConflictCandidateID: $selectedConflictCandidateID,
                onSelectPlace: onSelectPlace
            )
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    TracesBadge(selectedPlaceFilterKey == nil ? "Overview" : "Place filtered", systemImage: "scope", tint: .accentColor)
                    if let selectedEvent, !selectedEvent.suppressedCandidates.isEmpty {
                        TracesBadge("Conflict candidates", systemImage: "exclamationmark.triangle.fill", tint: TracesTheme.warning)
                    }
                }
                .padding(12)
            }
        }
    }
}

/// AppKit MapKit bridge used by SwiftUI.
struct EventMapView: NSViewRepresentable {
    let events: [ICSEvent]
    @Binding var selectedEventID: String?
    @Binding var selectedConflictCandidateID: String?
    let onSelectPlace: (String, String, String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedEventID: $selectedEventID,
            selectedConflictCandidateID: $selectedConflictCandidateID,
            onSelectPlace: onSelectPlace
        )
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsZoomControls = true
        map.showsCompass = true
        return map
    }

    func updateNSView(_ nsView: MKMapView, context: Context) {
        context.coordinator.selectedEventID = $selectedEventID
        context.coordinator.selectedConflictCandidateID = $selectedConflictCandidateID
        context.coordinator.onSelectPlace = onSelectPlace
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
                placeKey: TracesViewModel.placeKey(for: event),
                placeTitle: TracesViewModel.placeTitle(for: event),
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
                    placeKey: TracesViewModel.placeKey(for: event),
                    placeTitle: TracesViewModel.placeTitle(for: event),
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
            let candidatePlaceKey = candidate.placeID.isEmpty
                ? String(format: "coord:%.5f,%.5f", lat, lon)
                : "placeID:\(candidate.placeID)"

            annotations.append(
                TracesMapAnnotation(
                    eventID: event.id,
                    candidateID: candidate.id,
                    placeKey: candidatePlaceKey,
                    placeTitle: candidate.title,
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
        var selectedEventID: Binding<String?>
        var selectedConflictCandidateID: Binding<String?>
        var onSelectPlace: (String, String, String) -> Void
        var isApplyingSwiftUIUpdate = false

        init(
            selectedEventID: Binding<String?>,
            selectedConflictCandidateID: Binding<String?>,
            onSelectPlace: @escaping (String, String, String) -> Void
        ) {
            self.selectedEventID = selectedEventID
            self.selectedConflictCandidateID = selectedConflictCandidateID
            self.onSelectPlace = onSelectPlace
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard !isApplyingSwiftUIUpdate else {
                return
            }

            guard let annotation = view.annotation as? TracesMapAnnotation else {
                return
            }

            DispatchQueue.main.async {
                self.onSelectPlace(annotation.eventID, annotation.placeKey, annotation.placeTitle)

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
    let placeKey: String
    let placeTitle: String
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
        placeKey: String,
        placeTitle: String,
        label: String,
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D
    ) {
        self.eventID = eventID
        self.candidateID = candidateID
        self.placeKey = placeKey
        self.placeTitle = placeTitle
        self.label = label
        self.annotationTitle = title
        self.annotationSubtitle = subtitle
        self.coordinate = coordinate
        super.init()
    }
}
