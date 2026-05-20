import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    @State private var events: [ICSEvent] = []
    @State private var selectedEventID: String?
    @State private var fileName: String = "Open .ics or Timeline JSON"
    @State private var query: String = ""
    @State private var status: String = ""
    @State private var generatedICS: String = ""
    @State private var isGenerating = false
    @State private var showingGeneratorSettings = false
    @State private var cacheCount: Int = 0

    @AppStorage("traces.googleAPIKey") private var googleAPIKey: String = ""
    @AppStorage("traces.lastDays") private var lastDays: Int = 14
    @AppStorage("traces.minStayMinutes") private var minStayMinutes: Double = 15
    @AppStorage("traces.removeHomeOverMinutes") private var removeHomeOverMinutes: Double = 60

    private var selectedEvent: ICSEvent? {
        events.first { $0.id == selectedEventID }
    }

    private var filteredEvents: [ICSEvent] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return events }

        return events.filter {
            $0.summary.lowercased().contains(q)
            || $0.location.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationSplitView {
            GeometryReader { proxy in
                let compact = proxy.size.width < 240
                let ultraCompact = proxy.size.width < 150

                VStack(spacing: 0) {
                    toolbar(compact: compact, ultraCompact: ultraCompact)
                        .padding(.horizontal, compact ? 8 : 12)
                        .padding(.vertical, 10)

                    if !ultraCompact {
                        TextField("Search title / location / description", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 90)
                            .padding(.horizontal, compact ? 8 : 12)
                            .padding(.bottom, 8)
                    }

                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.bottom, 6)
                    }

                    if !status.isEmpty && !compact {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }

                    List(filteredEvents, selection: $selectedEventID) { event in
                        EventRow(event: event, compact: compact)
                            .tag(event.id)
                            .contentShape(Rectangle())
                    }
                    .onChange(of: selectedEventID) {
                        saveCurrentSession()
                    }
                }
            }
            .navigationTitle("Traces")
            .navigationSplitViewColumnWidth(min: 120, ideal: 340, max: 560)
        } detail: {
            if let event = selectedEvent {
                EventDetailView(event: event)
            } else {
                ContentUnavailableView(
                    "No event selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open an .ics file, or generate events from Google Timeline JSON.")
                )
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            restoreLastSession()
            refreshCacheCount()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }

                DispatchQueue.main.async {
                    loadFile(url)
                }
            }

            return true
        }
    }

    @ViewBuilder
    private func toolbar(compact: Bool, ultraCompact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            Menu {
                Button("Open ICS Preview") {
                    openFile(allowedExtensions: ["ics"])
                }

                Button("Open Timeline JSON & Generate") {
                    openFile(allowedExtensions: ["json"])
                }

                Divider()

                Button("Clear Last Session") {
                    clearLastSession()
                }
                .disabled(events.isEmpty && generatedICS.isEmpty)
            } label: {
                if compact {
                    Label("Open", systemImage: "folder")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Open", systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.bordered)
            .help("Open ICS or Timeline JSON")

            Button {
                showingGeneratorSettings.toggle()
            } label: {
                Label("Generate Settings", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingGeneratorSettings, arrowEdge: .bottom) {
                TimelineGeneratorSettingsView(
                    googleAPIKey: $googleAPIKey,
                    lastDays: $lastDays,
                    minStayMinutes: $minStayMinutes,
                    removeHomeOverMinutes: $removeHomeOverMinutes,
                    cacheCount: cacheCount,
                    onClearCache: clearLocationCache
                )
            }
            .help("Timeline generation settings")

            if !compact {
                Text(fileName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                exportICS()
            } label: {
                if compact {
                    Label("Export ICS", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                } else {
                    Label("Export ICS", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(events.isEmpty)

            if !compact {
                Text("\(filteredEvents.count) events")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            } else if !ultraCompact {
                Text("\(filteredEvents.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .fixedSize()
            }
        }
    }

    private func openFile(allowedExtensions: [String]) {
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

    private func loadFile(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            if ext == "json" {
                loadTimelineJSON(data: data, fileName: url.lastPathComponent)
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                let parsed = ICSParser.parse(text)

                self.events = parsed
                self.generatedICS = text
                self.selectedEventID = parsed.first?.id
                self.fileName = url.lastPathComponent
                self.status = "Loaded \(parsed.count) events from ICS."

                saveCurrentSession()
            }
        } catch {
            self.events = []
            self.generatedICS = ""
            self.selectedEventID = nil
            self.status = "Failed: \(error.localizedDescription)"
            self.isGenerating = false

            saveCurrentSession()
        }
    }

    private func loadTimelineJSON(data: Data, fileName: String) {
        let options = TimelineOptions(
            lastDays: lastDays,
            minStayMinutes: minStayMinutes,
            removeHomeOverMinutes: removeHomeOverMinutes
        )

        isGenerating = true
        status = googleAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Generating with local cache/fallback only. Add Google API key for uncached place names."
            : "Resolving unique placeIDs with local cache first..."

        Task {
            do {
                let generated = try await TimelineProcessor.generateEvents(
                    from: data,
                    options: options,
                    apiKey: googleAPIKey
                )

                let cacheCount = await LocationCacheStore.shared.count()
                let icsText = ICSWriter.makeICS(events: generated)

                await MainActor.run {
                    self.events = generated
                    self.generatedICS = icsText
                    self.selectedEventID = generated.first?.id
                    self.fileName = fileName
                    self.cacheCount = cacheCount
                    self.status = "Generated \(generated.count) events. Location cache: \(cacheCount)."
                    self.isGenerating = false

                    self.saveCurrentSession()
                }
            } catch {
                await MainActor.run {
                    self.events = []
                    self.generatedICS = ""
                    self.selectedEventID = nil
                    self.status = "Failed: \(error.localizedDescription)"
                    self.isGenerating = false

                    self.saveCurrentSession()
                }
            }
        }
    }

    private func exportICS() {
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

    private func restoreLastSession() {
        Task {
            let session = await SessionStore.shared.load()

            guard let session else {
                return
            }

            let cacheCount = await LocationCacheStore.shared.count()

            await MainActor.run {
                self.events = session.events
                self.selectedEventID = session.selectedEventID
                self.fileName = session.fileName
                self.generatedICS = session.generatedICS
                self.cacheCount = cacheCount

                if !session.events.isEmpty {
                    self.status = "Restored \(session.events.count) events from last session."
                }
            }
        }
    }

    private func saveCurrentSession() {
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

    private func clearLastSession() {
        events = []
        selectedEventID = nil
        fileName = "Open .ics or Timeline JSON"
        query = ""
        status = "Last session cleared."
        generatedICS = ""

        Task {
            await SessionStore.shared.clear()
        }
    }

    private func refreshCacheCount() {
        Task {
            let count = await LocationCacheStore.shared.count()

            await MainActor.run {
                self.cacheCount = count
            }
        }
    }

    private func clearLocationCache() {
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
