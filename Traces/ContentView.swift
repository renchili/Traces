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
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 560)
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
            VStack(spacing: 12) {
                toolbar
                exportScopeBar
                exportSelectionActions

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search events, locations, resolver notes", text: $viewModel.query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(TracesTheme.softBorder, lineWidth: 1))

                TracesStatusBanner(status: viewModel.status, isLoading: viewModel.isGenerating)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.displayEvents) { event in
                            exportableEventRow(event)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    TracesBadge("\(viewModel.displayEvents.count) events", systemImage: "calendar", tint: .accentColor)
                    TracesBadge("\(viewModel.exportEvents.count) selected", systemImage: "checkmark.circle", tint: viewModel.exportEvents.isEmpty ? .secondary : .green)
                    Spacer(minLength: 8)
                    Text(viewModel.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(12)
        }
    }

    private func exportableEventRow(_ event: ICSEvent) -> some View {
        let isSelectedForExport = viewModel.isSelectedForExport(event)
        let isSelectedEvent = event.id == viewModel.selectedEventID
        let isNew = viewModel.isNewlyAdded(event)
        let isLatest = viewModel.isLatestImport(event)
        let isUnexported = viewModel.isUnexported(event)

        return HStack(alignment: .top, spacing: 8) {
            Button {
                viewModel.toggleExportSelection(event.id)
            } label: {
                Image(systemName: isSelectedForExport ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelectedForExport ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .help(isSelectedForExport ? "Remove from export" : "Add to export")

            VStack(alignment: .leading, spacing: 6) {
                EventRow(event: event, compact: false)

                HStack(spacing: 6) {
                    if isNew {
                        TracesBadge("NEW", systemImage: "sparkles", tint: .green)
                    }

                    if isLatest && !isNew {
                        TracesBadge("LATEST IMPORT", systemImage: "tray.and.arrow.down", tint: .accentColor)
                    }

                    if isUnexported {
                        TracesBadge("UNEXPORTED", systemImage: "exclamationmark.circle.fill", tint: TracesTheme.warning)
                    } else {
                        TracesBadge("EXPORTED", systemImage: "checkmark.seal.fill", tint: .secondary)
                    }

                    if isSelectedForExport {
                        TracesBadge("SELECTED", systemImage: "checkmark.circle.fill", tint: .blue)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .background(
            RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                .fill(rowBackground(isSelectedEvent: isSelectedEvent, isSelectedForExport: isSelectedForExport, isUnexported: isUnexported))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                .stroke(rowBorder(isSelectedEvent: isSelectedEvent, isSelectedForExport: isSelectedForExport, isUnexported: isUnexported), lineWidth: isSelectedForExport || isUnexported ? 1.4 : 1)
        )
        .shadow(color: Color.black.opacity(isSelectedEvent ? 0.07 : 0.025), radius: 8, x: 0, y: 4)
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
            return Color.green.opacity(0.075)
        }

        if isUnexported {
            return TracesTheme.warning.opacity(0.075)
        }

        return Color.primary.opacity(0.035)
    }

    private func rowBorder(isSelectedEvent: Bool, isSelectedForExport: Bool, isUnexported: Bool) -> Color {
        if isSelectedEvent {
            return Color.accentColor.opacity(0.60)
        }

        if isSelectedForExport {
            return Color.green.opacity(0.45)
        }

        if isUnexported {
            return TracesTheme.warning.opacity(0.45)
        }

        return TracesTheme.softBorder
    }

    private var toolbar: some View {
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
                Label("Settings", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
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
                Label("Export ICS", systemImage: "calendar.badge.plus")
                    .labelStyle(.titleAndIcon)
            }
            .help(viewModel.exportScopeDescription)
            .buttonStyle(TracesIconButtonStyle(prominent: true))
            .disabled(viewModel.exportEvents.isEmpty)
        }
    }

    private var exportScopeBar: some View {
        HStack(spacing: 8) {
            TracesBadge(
                viewModel.exportScopeDescription,
                systemImage: "tray.and.arrow.up",
                tint: viewModel.exportEvents.isEmpty ? .secondary : Color.accentColor
            )

            Spacer(minLength: 6)

            Text("Click checkboxes or use quick select")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TracesTheme.softBorder, lineWidth: 1))
    }

    private var exportSelectionActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("Latest") {
                    viewModel.selectLatestImportForExport()
                }
                .buttonStyle(TracesIconButtonStyle())
                .disabled(viewModel.latestImportEventIDs.isEmpty)

                Button("Unexported") {
                    viewModel.selectUnexportedForExport()
                }
                .buttonStyle(TracesIconButtonStyle())

                Button("Filtered") {
                    viewModel.selectFilteredEventsForExport()
                }
                .buttonStyle(TracesIconButtonStyle())
                .disabled(viewModel.filteredEvents.isEmpty)
            }

            HStack(spacing: 8) {
                Button("All") {
                    viewModel.selectAllEventsForExport()
                }
                .buttonStyle(TracesIconButtonStyle())
                .disabled(viewModel.events.isEmpty)

                Button("Clear") {
                    viewModel.clearExportSelection()
                }
                .buttonStyle(TracesIconButtonStyle())
                .disabled(viewModel.selectedExportEventIDs.isEmpty)

                Spacer(minLength: 0)
            }
        }
    }

    private var middleMapAndDetail: some View {
        VSplitView {
            EventMapPanel(
                events: viewModel.filteredEvents,
                selectedEventID: $viewModel.selectedEventID,
                selectedConflictCandidateID: $viewModel.selectedConflictCandidateID
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
