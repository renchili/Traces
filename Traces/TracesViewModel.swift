import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

// MARK: - Main view model
// Owns user-visible application state and coordinates services.
// Views should call this object for actions instead of parsing files, exporting
// ICS, resolving places, or mutating the event list directly.

@MainActor
final class TracesViewModel: ObservableObject {
    @Published var events: [ICSEvent] = []
    @Published var selectedEventID: String?
    @Published var selectedConflictCandidateID: String?
    @Published var fileName: String = "Open .ics or Timeline JSON"
    @Published var query: String = ""
    @Published var status: String = ""
    @Published var generatedICS: String = ""
    @Published var isGenerating = false
    @Published var showingGeneratorSettings = false
    @Published var cacheCount: Int = 0

    var googleAPIKey: String {
        get { UserDefaults.standard.string(forKey: "traces.googleAPIKey") ?? "" }
        set {
            UserDefaults.standard.set(newValue, forKey: "traces.googleAPIKey")
            objectWillChange.send()
        }
    }

    var lastDays: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "traces.lastDays")
            return value == 0 ? 14 : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "traces.lastDays")
            objectWillChange.send()
        }
    }

    var minStayMinutes: Double {
        get {
            let value = UserDefaults.standard.double(forKey: "traces.minStayMinutes")
            return value == 0 ? 15 : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "traces.minStayMinutes")
            objectWillChange.send()
        }
    }

    var removeHomeOverMinutes: Double {
        get {
            let value = UserDefaults.standard.double(forKey: "traces.removeHomeOverMinutes")
            return value == 0 ? 60 : value
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "traces.removeHomeOverMinutes")
            objectWillChange.send()
        }
    }

    var selectedEvent: ICSEvent? {
        events.first { $0.id == selectedEventID }
    }

    // Raw filtered events keep the underlying chronological order for map/timeline/export logic.
    var filteredEvents: [ICSEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return events }

        return events.filter {
            $0.summary.lowercased().contains(q)
            || $0.location.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
        }
    }

    // Sidebar display order is newest first so newly imported Timeline JSON is immediately visible.
    var displayEvents: [ICSEvent] {
        filteredEvents.sorted { lhs, rhs in
            let lhsDate = lhs.start ?? lhs.end ?? .distantPast
            let rhsDate = rhs.start ?? rhs.end ?? .distantPast

            if lhsDate == rhsDate {
                return lhs.summary.localizedCaseInsensitiveCompare(rhs.summary) == .orderedAscending
            }

            return lhsDate > rhsDate
        }
    }

    func onAppear() {
        restoreLastSession()
        refreshCacheCount()
    }

    func didSelectEventChanged() {
        selectedConflictCandidateID = nil
        saveCurrentSession()
    }

    func promoteSelectedConflictCandidate() {
        guard
            let selectedEventID = selectedEventID,
            let conflictCandidateID = selectedConflictCandidateID,
            let eventIndex = events.firstIndex(where: { $0.id == selectedEventID }),
            let candidate = events[eventIndex].suppressedCandidates.first(where: { $0.id == conflictCandidateID })
        else {
            return
        }

        let oldEvent = events[eventIndex]
        let promoted = promote(candidate: candidate, in: oldEvent)

        events[eventIndex] = promoted
        self.selectedConflictCandidateID = nil
        generatedICS = ICSWriter.makeICS(events: events)
        status = "Replaced final event location with \(candidate.title)."
        saveCurrentSession()
    }

    private func promote(candidate: SuppressedCandidate, in event: ICSEvent) -> ICSEvent {
        let oldPrimary = SuppressedCandidate(
            id: "old-primary-\(event.id)",
            title: event.summary,
            placeID: extractPlaceID(from: event) ?? "",
            lat: event.lat,
            lon: event.lon,
            start: event.start,
            end: event.end,
            distanceMetersFromPrimary: distanceMeters(
                lat1: candidate.lat,
                lon1: candidate.lon,
                lat2: event.lat,
                lon2: event.lon
            )
        )

        var newSuppressed = event.suppressedCandidates.filter { $0.id != candidate.id }
        newSuppressed.insert(oldPrimary, at: 0)

        let normalizedSuppressed = newSuppressed.map { item in
            SuppressedCandidate(
                id: item.id,
                title: item.title,
                placeID: item.placeID,
                lat: item.lat,
                lon: item.lon,
                start: item.start,
                end: item.end,
                distanceMetersFromPrimary: distanceMeters(
                    lat1: candidate.lat,
                    lon1: candidate.lon,
                    lat2: item.lat,
                    lon2: item.lon
                )
            )
        }

        let newLocation = candidateLocation(candidate)
        let newURL = candidateMapURL(candidate)
        let newDescription = updatedDescription(
            oldDescription: event.description,
            newTitle: candidate.title,
            newLocation: newLocation,
            newURL: newURL
        )

        return ICSEvent(
            id: event.id,
            summary: candidate.title,
            location: newLocation,
            description: newDescription,
            url: newURL,
            start: event.start,
            end: event.end,
            lat: candidate.lat,
            lon: candidate.lon,
            suppressedCandidates: normalizedSuppressed
        )
    }

    private func candidateLocation(_ candidate: SuppressedCandidate) -> String {
        if let lat = candidate.lat, let lon = candidate.lon {
            return String(format: "%.6f, %.6f", lat, lon)
        }

        if !candidate.placeID.isEmpty {
            return "Place ID: \(candidate.placeID)"
        }

        return candidate.title
    }

    private func candidateMapURL(_ candidate: SuppressedCandidate) -> String {
        if !candidate.placeID.isEmpty {
            return "https://www.google.com/maps/place/?q=place_id:\(candidate.placeID)"
        }

        if let lat = candidate.lat, let lon = candidate.lon {
            return String(
                format: "https://www.google.com/maps/search/?api=1&query=%.7f,%.7f",
                lat,
                lon
            )
        }

        return ""
    }

    private func updatedDescription(
        oldDescription: String,
        newTitle: String,
        newLocation: String,
        newURL: String
    ) -> String {
        var lines = oldDescription.components(separatedBy: .newlines)

        lines.removeAll {
            $0.hasPrefix("Manual replacement:")
            || $0.hasPrefix("Final selected location:")
            || $0.hasPrefix("Final selected map:")
        }

        lines.append("")
        lines.append("Manual replacement: user selected conflict candidate as final event.")
        lines.append("Final selected location: \(newTitle) · \(newLocation)")

        if !newURL.isEmpty {
            lines.append("Final selected map: \(newURL)")
        }

        return lines.joined(separator: "\n")
    }

    private func extractPlaceID(from event: ICSEvent) -> String? {
        let combined = "\(event.url)\n\(event.description)\n\(event.location)"

        if let range = combined.range(of: "place_id:") {
            let suffix = combined[range.upperBound...]
            let placeID = suffix.prefix { char in
                char.isLetter || char.isNumber || char == "_" || char == "-"
            }

            let value = String(placeID)
            return value.isEmpty ? nil : value
        }

        if let range = combined.range(of: "Place ID:") {
            let suffix = combined[range.upperBound...]
            let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            let placeID = trimmed.prefix { char in
                char.isLetter || char.isNumber || char == "_" || char == "-"
            }

            let value = String(placeID)
            return value.isEmpty ? nil : value
        }

        return nil
    }

    private func distanceMeters(
        lat1: Double?,
        lon1: Double?,
        lat2: Double?,
        lon2: Double?
    ) -> Double? {
        guard let lat1, let lon1, let lat2, let lon2 else { return nil }

        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180

        let a =
            sin(dp / 2) * sin(dp / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)

        return 2 * r * asin(sqrt(a))
    }

    func openFile(allowedExtensions: [String]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = allowedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url)
        }
    }

    func loadFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            if ext == "json" {
                importTimelineJSON(data: data, fileName: url.lastPathComponent)
            } else {
                openICSPreview(url: url)
            }
        } catch {
            status = "Failed: \(error.localizedDescription)"
            isGenerating = false
        }
    }

    func openICSPreview(url: URL) {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = ICSParser.parse(text)

            events = parsed
            generatedICS = text
            selectedEventID = parsed.first?.id
            selectedConflictCandidateID = nil
            fileName = url.lastPathComponent
            status = "Loaded \(parsed.count) events from ICS preview."

            saveCurrentSession()
        } catch {
            events = []
            generatedICS = ""
            selectedEventID = nil
            selectedConflictCandidateID = nil
            status = "Failed: \(error.localizedDescription)"
            isGenerating = false

            saveCurrentSession()
        }
    }

    func importTimelineJSON(data: Data, fileName: String) {
        let options = TimelineOptions(
            lastDays: lastDays,
            minStayMinutes: minStayMinutes,
            removeHomeOverMinutes: removeHomeOverMinutes
        )

        let oldEvents = events

        isGenerating = true
        status = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Importing with local cache/fallback only."
            : "Importing and resolving unique placeIDs with local cache first..."

        Task {
            do {
                let importedEvents = try await TimelineProcessor.generateEvents(
                    from: data,
                    options: options,
                    apiKey: googleAPIKey
                )

                let mergeResult = EventUpsertService.merge(
                    existing: oldEvents,
                    imported: importedEvents
                )

                let cacheCount = await LocationCacheStore.shared.count()
                let icsText = ICSWriter.makeICS(events: mergeResult.events)
                let newestImportedEventID = importedEvents.max { lhs, rhs in
                    let lhsDate = lhs.start ?? lhs.end ?? .distantPast
                    let rhsDate = rhs.start ?? rhs.end ?? .distantPast
                    return lhsDate < rhsDate
                }?.id

                await MainActor.run {
                    self.events = mergeResult.events
                    self.generatedICS = icsText

                    if let newestImportedEventID,
                       mergeResult.events.contains(where: { $0.id == newestImportedEventID }) {
                        self.selectedEventID = newestImportedEventID
                        self.selectedConflictCandidateID = nil
                    } else if self.selectedEventID == nil
                        || !mergeResult.events.contains(where: { $0.id == self.selectedEventID }) {
                        self.selectedEventID = mergeResult.events.last?.id
                        self.selectedConflictCandidateID = nil
                    }

                    self.fileName = "Merged: \(fileName)"
                    self.cacheCount = cacheCount
                    self.status = "Imported \(importedEvents.count). Added \(mergeResult.addedCount), updated \(mergeResult.updatedCount), total \(mergeResult.events.count). Cache: \(cacheCount)."
                    self.isGenerating = false

                    self.saveCurrentSession()
                }
            } catch {
                await MainActor.run {
                    self.status = "Import failed: \(error.localizedDescription)"
                    self.isGenerating = false
                    self.saveCurrentSession()
                }
            }
        }
    }

    func currentICSText() -> String {
        generatedICS.isEmpty
            ? ICSWriter.makeICS(events: events)
            : generatedICS
    }

    func exportICS() {
        generatedICS = currentICSText()
    }

    func restoreLastSession() {
        Task {
            let session = await SessionStore.shared.load()

            guard let session else { return }

            let cacheCount = await LocationCacheStore.shared.count()

            await MainActor.run {
                self.events = session.events
                self.selectedEventID = session.selectedEventID
                self.selectedConflictCandidateID = nil
                self.fileName = session.fileName
                self.generatedICS = session.generatedICS
                self.cacheCount = cacheCount

                if !session.events.isEmpty {
                    self.status = "Restored \(session.events.count) events from last session."
                }
            }
        }
    }

    func saveCurrentSession() {
        let session = TracesSession(
            events: events,
            selectedEventID: selectedEventID,
            fileName: fileName,
            generatedICS: generatedICS,
            savedAt: Date()
        )

        Task {
            await SessionStore.shared.save(session)
        }
    }

    func clearLastSession() {
        events = []
        selectedEventID = nil
        selectedConflictCandidateID = nil
        fileName = "Open .ics or Timeline JSON"
        query = ""
        status = "Last session cleared."
        generatedICS = ""

        Task {
            await SessionStore.shared.clear()
        }
    }

    func refreshCacheCount() {
        Task {
            let count = await LocationCacheStore.shared.count()

            await MainActor.run {
                self.cacheCount = count
            }
        }
    }

    func clearLocationCache() {
        Task {
            await LocationCacheStore.shared.clear()
            let count = await LocationCacheStore.shared.count()

            await MainActor.run {
                self.cacheCount = count
                self.status = "Location cache cleared."
            }
        }
    }
}
