import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class TracesViewModel: ObservableObject {
    @Published var events: [ICSEvent] = []
    @Published var selectedEventID: String?
    @Published var selectedConflictCandidateID: String?
    @Published var selectedPlaceFilterKey: String?
    @Published var selectedPlaceFilterTitle: String?
    @Published var fileName = "Open .ics or Timeline JSON"
    @Published var query = ""
    @Published var status = ""
    @Published var generatedICS = ""
    @Published var isGenerating = false
    @Published var showingGeneratorSettings = false
    @Published var cacheCount = 0
    @Published private(set) var latestImportEventIDs: Set<String> = []
    @Published private(set) var newlyAddedEventIDs: Set<String> = []
    @Published private(set) var exportedEventIDs: Set<String> = []
    @Published var selectedExportEventIDs: Set<String> = []

    var googleAPIKey: String { get { UserDefaults.standard.string(forKey: "traces.googleAPIKey") ?? "" } set { UserDefaults.standard.set(newValue, forKey: "traces.googleAPIKey"); objectWillChange.send() } }
    var lastDays: Int { get { let v = UserDefaults.standard.integer(forKey: "traces.lastDays"); return v == 0 ? 14 : v } set { UserDefaults.standard.set(newValue, forKey: "traces.lastDays"); objectWillChange.send() } }
    var minStayMinutes: Double { get { let v = UserDefaults.standard.double(forKey: "traces.minStayMinutes"); return v == 0 ? 15 : v } set { UserDefaults.standard.set(newValue, forKey: "traces.minStayMinutes"); objectWillChange.send() } }
    var removeHomeOverMinutes: Double { get { let v = UserDefaults.standard.double(forKey: "traces.removeHomeOverMinutes"); return v == 0 ? 60 : v } set { UserDefaults.standard.set(newValue, forKey: "traces.removeHomeOverMinutes"); objectWillChange.send() } }
    var excludedPlaceRulesText: String { get { UserDefaults.standard.string(forKey: "traces.excludedPlaceRulesText") ?? "home\n家" } set { UserDefaults.standard.set(newValue, forKey: "traces.excludedPlaceRulesText"); objectWillChange.send() } }
    private var excludedPlaceRules: [String] { excludedPlaceRulesText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty && !$0.hasPrefix("#") } }

    var selectedEvent: ICSEvent? { events.first { $0.id == selectedEventID } }
    var filteredEvents: [ICSEvent] { let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return events.filter { e in (selectedPlaceFilterKey.map { Self.placeKey(for: e) == $0 } ?? true) && (q.isEmpty || e.summary.lowercased().contains(q) || e.location.lowercased().contains(q) || e.description.lowercased().contains(q)) } }
    var displayEvents: [ICSEvent] { filteredEvents.sorted { a, b in let da = a.start ?? a.end ?? .distantPast; let db = b.start ?? b.end ?? .distantPast; return da == db ? a.summary.localizedCaseInsensitiveCompare(b.summary) == .orderedAscending : da > db } }
    var exportEvents: [ICSEvent] { selectedExportEventIDs.isEmpty ? [] : events.filter { selectedExportEventIDs.contains($0.id) } }
    var exportScopeDescription: String { let s = exportEvents.count; let t = events.count; let u = events.filter { !isExported($0) }.count; return s == t && t > 0 ? "Full export selected · \(s) events" : "Selected export · \(s) events · \(u) unexported" }
    var placeFilterDescription: String? { guard let k = selectedPlaceFilterKey else { return nil }; return "\(selectedPlaceFilterTitle ?? k) · \(eventsForPlaceKey(k).count) visits" }

    func onAppear() { restoreLastSession(); refreshCacheCount() }
    func didSelectEventChanged() { selectedConflictCandidateID = nil; saveCurrentSession() }

    static func placeKey(for e: ICSEvent) -> String { if let p = extractPlaceID(fromText: "\(e.url)\n\(e.description)\n\(e.location)") { return "placeID:\(p)" }; if let lat = e.lat, let lon = e.lon { return String(format: "coord:%.5f,%.5f", lat, lon) }; let l = e.location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression); return l.isEmpty ? "title:\(e.summary.lowercased())" : "location:\(l)" }
    static func placeTitle(for e: ICSEvent) -> String { !e.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? e.summary : (!e.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? e.location : placeKey(for: e)) }
    func selectPlaceFilter(eventID: String, placeKey: String, placeTitle: String) { selectedPlaceFilterKey = placeKey; selectedPlaceFilterTitle = placeTitle; selectedEventID = lastEventForPlaceKey(placeKey)?.id ?? eventID; selectedConflictCandidateID = nil; status = "Filtered by place: \(placeTitle). Showing \(filteredEvents.count) visits."; saveCurrentSession() }
    func clearPlaceFilter() { selectedPlaceFilterKey = nil; selectedPlaceFilterTitle = nil; status = "Cleared place filter."; saveCurrentSession() }
    func eventsForPlaceKey(_ k: String) -> [ICSEvent] { events.filter { Self.placeKey(for: $0) == k } }
    func lastEventForPlaceKey(_ k: String) -> ICSEvent? { eventsForPlaceKey(k).max { ($0.start ?? $0.end ?? .distantPast) < ($1.start ?? $1.end ?? .distantPast) } }

    func isLatestImport(_ e: ICSEvent) -> Bool { latestImportEventIDs.contains(e.id) }
    func isNewlyAdded(_ e: ICSEvent) -> Bool { newlyAddedEventIDs.contains(e.id) }
    func isUnexported(_ e: ICSEvent) -> Bool { !isExported(e) }
    func isSelectedForExport(_ e: ICSEvent) -> Bool { selectedExportEventIDs.contains(e.id) }
    func toggleExportSelection(_ id: String) { selectedExportEventIDs.contains(id) ? selectedExportEventIDs.remove(id) : selectedExportEventIDs.insert(id); generatedICS = currentICSText(); saveCurrentSession() }
    func selectLatestImportForExport() { selectedExportEventIDs = latestImportEventIDs.intersection(Set(events.map(\.id))); generatedICS = currentICSText(); status = "Selected latest import for export: \(exportEvents.count) events."; saveCurrentSession() }
    func selectUnexportedForExport() { selectedExportEventIDs = Set(events.filter { !isExported($0) }.map(\.id)); generatedICS = currentICSText(); status = "Selected unexported events: \(exportEvents.count) events."; saveCurrentSession() }
    func selectFilteredEventsForExport() { selectedExportEventIDs = Set(filteredEvents.map(\.id)); generatedICS = currentICSText(); status = "Selected current search/filter results: \(exportEvents.count) events."; saveCurrentSession() }
    func selectAllEventsForExport() { selectedExportEventIDs = Set(events.map(\.id)); generatedICS = currentICSText(); status = "Selected full export: \(exportEvents.count) events."; saveCurrentSession() }
    func clearExportSelection() { selectedExportEventIDs = []; generatedICS = ""; status = "Cleared export selection."; saveCurrentSession() }
    func markCurrentExported() { let xs = exportEvents; let ids = Set(xs.map(\.id)); exportedEventIDs.formUnion(ids); exportedEventIDs.formUnion(Set(xs.map { Self.exportTrackingKey(for: $0) })); newlyAddedEventIDs.subtract(ids); selectedExportEventIDs.subtract(ids); generatedICS = currentICSText(); saveCurrentSession() }
    func ignoreSelectedPlace() { guard let e = selectedEvent else { return }; let r = exclusionRule(for: e); var lines = excludedPlaceRulesText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }; if !lines.map({ $0.lowercased() }).contains(r.lowercased()) { lines.append(r) }; excludedPlaceRulesText = lines.joined(separator: "\n"); let ids = Set(events.filter { isExcludedPlace($0) }.map(\.id)); removeEvents(ids); status = "Ignored place rule: \(r)."; saveCurrentSession() }
    private func removeEvents(_ ids: Set<String>) { events.removeAll { ids.contains($0.id) }; latestImportEventIDs.subtract(ids); newlyAddedEventIDs.subtract(ids); selectedExportEventIDs.subtract(ids); exportedEventIDs.subtract(ids); if let id = selectedEventID, ids.contains(id) { selectedEventID = events.last?.id }; generatedICS = currentICSText() }
    private func isExported(_ e: ICSEvent) -> Bool { exportedEventIDs.contains(e.id) || exportedEventIDs.contains(Self.exportTrackingKey(for: e)) }
    private static func exportTrackingKey(for e: ICSEvent) -> String { "upsert:\(EventUpsertService.eventUpsertKey(e))" }

    func promoteSelectedConflictCandidate() { guard let sid = selectedEventID, let cid = selectedConflictCandidateID, let i = events.firstIndex(where: { $0.id == sid }), let c = events[i].suppressedCandidates.first(where: { $0.id == cid }) else { return }; let p = promote(candidate: c, in: events[i]); events[i] = p; latestImportEventIDs.insert(p.id); selectedExportEventIDs.insert(p.id); exportedEventIDs.remove(p.id); exportedEventIDs.remove(Self.exportTrackingKey(for: p)); if let k = selectedPlaceFilterKey, Self.placeKey(for: p) != k { clearPlaceFilter() }; selectedConflictCandidateID = nil; generatedICS = ICSWriter.makeICS(events: exportEvents); status = "Replaced final event location with \(c.title). Marked event as unexported."; saveCurrentSession() }
    private func promote(candidate c: SuppressedCandidate, in e: ICSEvent) -> ICSEvent { let old = SuppressedCandidate(id: "old-primary-\(e.id)", title: e.summary, placeID: extractPlaceID(from: e) ?? "", lat: e.lat, lon: e.lon, start: e.start, end: e.end, distanceMetersFromPrimary: distanceMeters(lat1: c.lat, lon1: c.lon, lat2: e.lat, lon2: e.lon)); var s = e.suppressedCandidates.filter { $0.id != c.id }; s.insert(old, at: 0); let ns = s.map { SuppressedCandidate(id: $0.id, title: $0.title, placeID: $0.placeID, lat: $0.lat, lon: $0.lon, start: $0.start, end: $0.end, distanceMetersFromPrimary: distanceMeters(lat1: c.lat, lon1: c.lon, lat2: $0.lat, lon2: $0.lon)) }; let loc = candidateLocation(c); let url = candidateMapURL(c); return ICSEvent(id: e.id, summary: c.title, location: loc, description: updatedDescription(oldDescription: e.description, newTitle: c.title, newLocation: loc, newURL: url), url: url, start: e.start, end: e.end, lat: c.lat, lon: c.lon, suppressedCandidates: ns) }
    private func candidateLocation(_ c: SuppressedCandidate) -> String { if let lat = c.lat, let lon = c.lon { return String(format: "%.6f, %.6f", lat, lon) }; return c.placeID.isEmpty ? c.title : "Place ID: \(c.placeID)" }
    private func candidateMapURL(_ c: SuppressedCandidate) -> String { if !c.placeID.isEmpty { return "https://www.google.com/maps/place/?q=place_id:\(c.placeID)" }; if let lat = c.lat, let lon = c.lon { return String(format: "https://www.google.com/maps/search/?api=1&query=%.7f,%.7f", lat, lon) }; return "" }
    private func updatedDescription(oldDescription: String, newTitle: String, newLocation: String, newURL: String) -> String { var xs = oldDescription.components(separatedBy: .newlines); xs.removeAll { $0.hasPrefix("Manual replacement:") || $0.hasPrefix("Final selected location:") || $0.hasPrefix("Final selected map:") }; xs += ["", "Manual replacement: user selected conflict candidate as final event.", "Final selected location: \(newTitle) · \(newLocation)"]; if !newURL.isEmpty { xs.append("Final selected map: \(newURL)") }; return xs.joined(separator: "\n") }
    private func extractPlaceID(from e: ICSEvent) -> String? { Self.extractPlaceID(fromText: "\(e.url)\n\(e.description)\n\(e.location)") }
    private static func extractPlaceID(fromText t: String) -> String? { if let r = t.range(of: "place_id:") { let v = String(t[r.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }); return v.isEmpty ? nil : v }; if let r = t.range(of: "Place ID:") { let trim = t[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines); let v = String(trim.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }); return v.isEmpty ? nil : v }; return nil }
    private func distanceMeters(lat1: Double?, lon1: Double?, lat2: Double?, lon2: Double?) -> Double? { guard let lat1, let lon1, let lat2, let lon2 else { return nil }; let r = 6_371_000.0, p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180, dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180; let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2); return 2 * r * asin(sqrt(a)) }

    func openFile(allowedExtensions: [String]) { let p = NSOpenPanel(); p.allowedContentTypes = allowedExtensions.compactMap { UTType(filenameExtension: $0) }; p.allowsMultipleSelection = false; p.canChooseDirectories = false; if p.runModal() == .OK, let u = p.url { loadFile(u) } }
    func loadFile(_ u: URL) { do { let data = try Data(contentsOf: u); u.pathExtension.lowercased() == "json" ? importTimelineJSON(data: data, fileName: u.lastPathComponent) : openICSPreview(url: u) } catch { status = "Failed: \(error.localizedDescription)"; isGenerating = false } }
    func openICSPreview(url u: URL) { do { let text = try String(contentsOf: u, encoding: .utf8); let parsed = ICSParser.parse(text); let ids = Set(parsed.map(\.id)); events = parsed; latestImportEventIDs = ids; newlyAddedEventIDs = ids; selectedExportEventIDs = ids; selectedPlaceFilterKey = nil; selectedPlaceFilterTitle = nil; generatedICS = ICSWriter.makeICS(events: parsed); selectedEventID = parsed.first?.id; selectedConflictCandidateID = nil; fileName = u.lastPathComponent; status = "Loaded \(parsed.count) events from ICS preview. Selected loaded file for export."; saveCurrentSession() } catch { events = []; latestImportEventIDs = []; newlyAddedEventIDs = []; selectedExportEventIDs = []; selectedPlaceFilterKey = nil; selectedPlaceFilterTitle = nil; generatedICS = ""; selectedEventID = nil; selectedConflictCandidateID = nil; status = "Failed: \(error.localizedDescription)"; isGenerating = false; saveCurrentSession() } }

    func importTimelineJSON(data: Data, fileName: String) {
        let options = TimelineOptions(lastDays: lastDays, minStayMinutes: minStayMinutes, removeHomeOverMinutes: removeHomeOverMinutes, excludedPlaceRules: excludedPlaceRules)
        let oldEvents = events, oldIDs = Set(events.map(\.id)), oldKeys = Set(events.map { Self.exportTrackingKey(for: $0) }), oldExported = exportedEventIDs
        isGenerating = true; status = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Importing with local cache/fallback only." : "Importing and resolving unique placeIDs with local cache first..."
        Task { do {
            let raw = try await TimelineProcessor.generateEvents(from: data, options: options, apiKey: googleAPIKey)
            let imported = raw.filter { !Self.isExcludedPlace($0, rules: options.excludedPlaceRules) }
            let merge = EventUpsertService.merge(existing: oldEvents, imported: imported)
            let cache = await LocationCacheStore.shared.count(), importedIDs = Set(imported.map(\.id))
            let newIDs = Set(imported.filter { !oldIDs.contains($0.id) && !oldKeys.contains(Self.exportTrackingKey(for: $0)) }.map(\.id))
            let updIDs = Set(imported.filter { oldIDs.contains($0.id) || oldKeys.contains(Self.exportTrackingKey(for: $0)) }.map(\.id))
            let unexpIDs = Set(imported.filter { !oldExported.contains($0.id) && !oldExported.contains(Self.exportTrackingKey(for: $0)) }.map(\.id))
            let newest = imported.max { ($0.start ?? $0.end ?? .distantPast) < ($1.start ?? $1.end ?? .distantPast) }?.id
            await MainActor.run { self.events = merge.events.filter { !self.isExcludedPlace($0) }; let live = Set(self.events.map(\.id)); self.latestImportEventIDs = importedIDs.intersection(live); self.newlyAddedEventIDs = newIDs.intersection(live); self.selectedExportEventIDs = unexpIDs.intersection(live); self.selectedPlaceFilterKey = nil; self.selectedPlaceFilterTitle = nil; self.generatedICS = ICSWriter.makeICS(events: self.events.filter { self.selectedExportEventIDs.contains($0.id) }); self.selectedEventID = (newest.flatMap { id in self.events.first { $0.id == id }?.id }) ?? (self.selectedEventID.flatMap { id in self.events.first { $0.id == id }?.id }) ?? self.events.last?.id; self.selectedConflictCandidateID = nil; self.fileName = "Merged: \(fileName)"; self.cacheCount = cache; self.status = "Imported \(imported.count). Skipped \(raw.count - imported.count) excluded. Selected unexported: \(self.exportEvents.count). New: \(self.newlyAddedEventIDs.count), re-imported/updated: \(updIDs.count). Cache: \(cache)."; self.isGenerating = false; self.saveCurrentSession() }
        } catch { await MainActor.run { self.status = "Import failed: \(error.localizedDescription)"; self.isGenerating = false; self.saveCurrentSession() } } }
    }

    func currentICSText() -> String { ICSWriter.makeICS(events: exportEvents) }
    func exportICS() { generatedICS = currentICSText() }
    func restoreLastSession() { Task { let s = await SessionStore.shared.load(); guard let s else { return }; let c = await LocationCacheStore.shared.count(); await MainActor.run { self.events = s.events.filter { !self.isExcludedPlace($0) }; self.selectedEventID = s.selectedEventID.flatMap { id in self.events.first { $0.id == id }?.id } ?? self.events.last?.id; self.selectedConflictCandidateID = nil; self.selectedPlaceFilterKey = nil; self.selectedPlaceFilterTitle = nil; self.fileName = s.fileName; self.generatedICS = s.generatedICS; self.cacheCount = c; self.latestImportEventIDs = s.latestImportEventIDs.intersection(Set(self.events.map(\.id))); self.exportedEventIDs = s.exportedEventIDs; self.exportedEventIDs.formUnion(s.events.filter { s.exportedEventIDs.contains($0.id) }.map { Self.exportTrackingKey(for: $0) }); let done = Set(s.events.filter { self.isExported($0) }.map(\.id)); self.newlyAddedEventIDs = s.newlyAddedEventIDs.subtracting(done).intersection(Set(self.events.map(\.id))); let sel = s.selectedExportEventIDs.isEmpty ? s.latestImportEventIDs : s.selectedExportEventIDs; self.selectedExportEventIDs = sel.subtracting(done).intersection(Set(self.events.map(\.id))); if !s.events.isEmpty { self.status = "Restored \(self.events.count) events from last session. \(self.exportScopeDescription)." } } } }
    func saveCurrentSession() { let s = TracesSession(events: events, selectedEventID: selectedEventID, fileName: fileName, generatedICS: generatedICS, savedAt: Date(), latestImportEventIDs: latestImportEventIDs, newlyAddedEventIDs: newlyAddedEventIDs, exportedEventIDs: exportedEventIDs, selectedExportEventIDs: selectedExportEventIDs); Task { await SessionStore.shared.save(s) } }
    func clearLastSession() { events = []; latestImportEventIDs = []; newlyAddedEventIDs = []; exportedEventIDs = []; selectedExportEventIDs = []; selectedPlaceFilterKey = nil; selectedPlaceFilterTitle = nil; selectedEventID = nil; selectedConflictCandidateID = nil; fileName = "Open .ics or Timeline JSON"; query = ""; status = "Last session cleared."; generatedICS = ""; Task { await SessionStore.shared.clear() } }
    func refreshCacheCount() { Task { let c = await LocationCacheStore.shared.count(); await MainActor.run { self.cacheCount = c } } }
    func clearLocationCache() { Task { await LocationCacheStore.shared.clear(); let c = await LocationCacheStore.shared.count(); await MainActor.run { self.cacheCount = c; self.status = "Location cache cleared." } } }
    private func exclusionRule(for e: ICSEvent) -> String { let k = Self.placeKey(for: e); if k.hasPrefix("placeID:") || k.hasPrefix("coord:") { return k }; return !e.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? e.summary : e.location }
    private func isExcludedPlace(_ e: ICSEvent) -> Bool { Self.isExcludedPlace(e, rules: excludedPlaceRules) }
    private static func isExcludedPlace(_ e: ICSEvent, rules: [String]) -> Bool { let h = [e.summary, e.location, e.description, e.url, placeKey(for: e)].joined(separator: "\n").lowercased(); return rules.contains { r in let x = r.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); return !x.isEmpty && h.contains(x) } }
}
