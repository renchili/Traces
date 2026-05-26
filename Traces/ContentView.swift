import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

// MARK: - Top-level app shell
// ContentView owns only the window layout and high-level bindings.
// Business logic lives in TracesViewModel; map/timeline/detail rendering lives
// in dedicated child view files.

struct ContentView: View {
    @StateObject private var viewModel = TracesViewModel()
    @State private var isShowingICSExporter = false
    @State private var exportDocument = ICSExportDocument()

    var body: some View {
        HSplitView {
            leftEventList
                .frame(minWidth: 320, idealWidth: 390, maxWidth: 520)
                .frame(maxHeight: .infinity, alignment: .top)

            middleMapAndDetail
                .frame(minWidth: 500, idealWidth: 780)
                .frame(maxHeight: .infinity, alignment: .top)

            rightTimelineWaterfall
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 480)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(minWidth: 1180, minHeight: 720)
        .background(
            LinearGradient(
                colors: [TracesTheme.appBackground, Color.accentColor.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            viewModel.onAppear()
        }
        .fileExporter(
            isPresented: $isShowingICSExporter,
            document: exportDocument,
            contentType: UTType(filenameExtension: "ics") ?? .data,
            defaultFilename: viewModel.exportEvents.count == viewModel.events.count ? "traces-full-export.ics" : "traces-selected-export.ics"
        ) { result in
            switch result {
            case let .success(url):
                viewModel.markCurrentExported()
                viewModel.status = "Exported \(viewModel.exportEvents.count) selected events to \(url.lastPathComponent)."
            case let .failure(error):
                viewModel.status = "Export failed: \(error.localizedDescription)"
            }
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
                    viewModel.loadFile(url)
                }
            }

            return true
        }
    }

    private var leftEventList: some View {
        TracesPanel(
            title: "Events",
            subtitle: "\(viewModel.displayEvents.count) shown · \(viewModel.events.count) total",
            systemImage: "list.bullet.rectangle"
        ) {
            VStack(spacing: 8) {
                compactToolbar
                compactSearchRow

                if let placeFilterDescription = viewModel.placeFilterDescription {
                    HStack(spacing: 6) {
                        TracesBadge(placeFilterDescription, systemImage: "mappin.and.ellipse", tint: .accentColor)
                        Spacer(minLength: 4)
                        Button {
                            viewModel.clearPlaceFilter()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Clear place filter")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
                }

                if viewModel.isGenerating || viewModel.status.lowercased().contains("failed") {
                    TracesStatusBanner(status: viewModel.status, isLoading: viewModel.isGenerating)
                }

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(viewModel.displayEvents) { event in
                            exportableEventRow(event)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                compactFooter
            }
            .padding(10)
        }
    }

    private var compactToolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Open ICS Preview") {
                    viewModel.openFile(allowedExtensions: ["ics"])
                }

                Button("Import Timeline JSON") {
                    viewModel.openFile(allowedExtensions: ["json"])
                }

                Divider()

                Button("Clear Last Session") {
                    viewModel.clearLastSession()
                }
                .disabled(viewModel.events.isEmpty && viewModel.generatedICS.isEmpty)
            } label: {
                Label("Open", systemImage: "folder")
            }
            .buttonStyle(TracesIconButtonStyle())

            Button {
                viewModel.showingGeneratorSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 18)
            }
            .buttonStyle(TracesIconButtonStyle())
            .popover(isPresented: $viewModel.showingGeneratorSettings, arrowEdge: .bottom) {
                TimelineGeneratorSettingsView(
                    googleAPIKey: Binding(
                        get: { viewModel.googleAPIKey },
                        set: { viewModel.googleAPIKey = $0 }
                    ),
                    lastDays: Binding(
                        get: { viewModel.lastDays },
                        set: { viewModel.lastDays = $0 }
                    ),
                    minStayMinutes: Binding(
                        get: { viewModel.minStayMinutes },
                        set: { viewModel.minStayMinutes = $0 }
                    ),
                    removeHomeOverMinutes: Binding(
                        get: { viewModel.removeHomeOverMinutes },
                        set: { viewModel.removeHomeOverMinutes = $0 }
                    ),
                    cacheCount: viewModel.cacheCount,
                    onClearCache: viewModel.clearLocationCache
                )
            }

            Spacer(minLength: 8)

            Button {
                exportDocument = ICSExportDocument(text: viewModel.currentICSText())
                isShowingICSExporter = true
            } label: {
                Label("Export", systemImage: "calendar.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .help(viewModel.exportScopeDescription)
            .buttonStyle(TracesIconButtonStyle(prominent: true))
            .disabled(viewModel.exportEvents.isEmpty)
        }
    }

    private var compactSearchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search events", text: $viewModel.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(TracesTheme.softBorder, lineWidth: 1))

            Menu {
                Button("Select latest import") {
                    viewModel.selectLatestImportForExport()
                }
                .disabled(viewModel.latestImportEventIDs.isEmpty)

                Button("Select unexported") {
                    viewModel.selectUnexportedForExport()
                }

                Button("Select filtered results") {
                    viewModel.selectFilteredEventsForExport()
                }
                .disabled(viewModel.filteredEvents.isEmpty)

                Divider()

                Button("Select all") {
                    viewModel.selectAllEventsForExport()
                }
                .disabled(viewModel.events.isEmpty)

                Button("Clear export selection") {
                    viewModel.clearExportSelection()
                }
                .disabled(viewModel.selectedExportEventIDs.isEmpty)
            } label: {
                Label("Select", systemImage: "checklist")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .buttonStyle(TracesIconButtonStyle())
            .help("Export selection")
        }
    }

    private var compactFooter: some View {
        HStack(spacing: 6) {
            TracesBadge("\(viewModel.exportEvents.count) selected", systemImage: "checkmark.circle", tint: viewModel.exportEvents.isEmpty ? .secondary : .green)
            TracesBadge("\(viewModel.displayEvents.count) shown", systemImage: "calendar", tint: .accentColor)
            Spacer(minLength: 6)
            Text(viewModel.fileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func exportableEventRow(_ event: ICSEvent) -> some View {
        let isSelectedForExport = viewModel.isSelectedForExport(event)
        let isSelectedEvent = event.id == viewModel.selectedEventID
        let isNew = viewModel.isNewlyAdded(event)
        let isLatest = viewModel.isLatestImport(event)
        let isUnexported = viewModel.isUnexported(event)

        return HStack(alignment: .top, spacing: 6) {
            Button {
                viewModel.toggleExportSelection(event.id)
            } label: {
                Image(systemName: isSelectedForExport ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelectedForExport ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 28)
            }
            .buttonStyle(.plain)
            .help(isSelectedForExport ? "Remove from export" : "Add to export")

            VStack(alignment: .leading, spacing: 2) {
                EventRow(event: event, compact: true)

                HStack(spacing: 5) {
                    if isNew {
                        TracesBadge("NEW", tint: .green)
                    } else if isLatest {
                        TracesBadge("LATEST", tint: .accentColor)
                    }

                    if isUnexported {
                        TracesBadge("UNEXPORTED", tint: TracesTheme.warning)
                    }

                    if isSelectedForExport {
                        TracesBadge("EXPORT", tint: .blue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 7)
        .background(
            RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                .fill(rowBackground(isSelectedEvent: isSelectedEvent, isSelectedForExport: isSelectedForExport, isUnexported: isUnexported))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                .stroke(rowBorder(isSelectedEvent: isSelectedEvent, isSelectedForExport: isSelectedForExport, isUnexported: isUnexported), lineWidth: isSelectedForExport || isUnexported ? 1.25 : 1)
        )
        .shadow(color: Color.black.opacity(isSelectedEvent ? 0.055 : 0.018), radius: 6, x: 0, y: 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.selectedEventID == event.id {
                viewModel.selectedEventID = nil
            } else {
                viewModel.selectedEventID = event.id
            }
            viewModel.didSelectEventChanged()
        }
    }

    private func rowBackground(isSelectedEvent: Bool, isSelectedForExport: Bool, isUnexported: Bool) -> Color {
        if isSelectedEvent {
            return Color.accentColor.opacity(0.14)
        }

        if isSelectedForExport {
            return Color.green.opacity(0.060)
        }

        if isUnexported {
            return TracesTheme.warning.opacity(0.060)
        }

        return Color.primary.opacity(0.030)
    }

    private func rowBorder(isSelectedEvent: Bool, isSelectedForExport: Bool, isUnexported: Bool) -> Color {
        if isSelectedEvent {
            return Color.accentColor.opacity(0.60)
        }

        if isSelectedForExport {
            return Color.green.opacity(0.42)
        }

        if isUnexported {
            return TracesTheme.warning.opacity(0.42)
        }

        return TracesTheme.softBorder
    }

    private var middleMapAndDetail: some View {
        VSplitView {
            EventMapPanel(
                events: viewModel.filteredEvents,
                selectedEventID: $viewModel.selectedEventID,
                selectedConflictCandidateID: $viewModel.selectedConflictCandidateID,
                selectedPlaceFilterKey: viewModel.selectedPlaceFilterKey,
                selectedPlaceFilterTitle: viewModel.selectedPlaceFilterTitle,
                onSelectPlace: { eventID, placeKey, placeTitle in
                    viewModel.selectPlaceFilter(
                        eventID: eventID,
                        placeKey: placeKey,
                        placeTitle: placeTitle
                    )
                },
                onClearPlaceFilter: {
                    viewModel.clearPlaceFilter()
                }
            )
            .frame(minHeight: 280, idealHeight: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            TracesPanel(
                title: viewModel.selectedEvent?.summary ?? "Event Detail",
                subtitle: viewModel.selectedEvent.map(dateRange),
                systemImage: "doc.text.magnifyingglass"
            ) {
                Group {
                    if let selectedEvent = viewModel.selectedEvent {
                        EventDetailView(
                            event: selectedEvent,
                            selectedConflictCandidateID: $viewModel.selectedConflictCandidateID,
                            onPromoteConflictCandidate: {
                                viewModel.promoteSelectedConflictCandidate()
                            }
                        )
                    } else {
                        ContentUnavailableView(
                            "No event selected",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("Select an event from the left list, timeline, or map.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 260)
            }
            .frame(minHeight: 280)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var rightTimelineWaterfall: some View {
        TimelineWaterfallView(
            events: viewModel.filteredEvents,
            selectedEventID: $viewModel.selectedEventID
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
