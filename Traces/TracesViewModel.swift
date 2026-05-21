import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

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
        get {
            UserDefaults.standard.string(forKey: "traces.googleAPIKey") ?? ""
        }
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

    var filteredEvents: [ICSEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            return events
        }

        return events.filter {
            $0.summary.lowercased().contains(q)
            || $0.location.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
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

                await MainActor.run {
                    self.events = mergeResult.events
                    self.generatedICS = icsText

                    if self.selectedEventID == nil
                        || !mergeResult.events.contains(where: { $0.id == self.selectedEventID }) {
                        self.selectedEventID = importedEvents.first?.id ?? mergeResult.events.first?.id
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

    func exportICS() {
        let icsText = generatedICS.isEmpty
            ? ICSWriter.makeICS(events: events)
            : generatedICS

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = "timeline-preview.ics"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try icsText.write(to: url, atomically: true, encoding: .utf8)
                status = "Exported \(events.count) events to \(url.lastPathComponent)."
            } catch {
                status = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func restoreLastSession() {
        Task {
            let session = await SessionStore.shared.load()

            guard let session else {
                return
            }

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
