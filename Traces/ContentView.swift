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
                .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)
                .frame(maxHeight: .infinity, alignment: .top)

            middleMapAndDetail
                .frame(minWidth: 500, idealWidth: 780)
                .frame(maxHeight: .infinity, alignment: .top)

            rightTimelineWaterfall
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 480)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(minWidth: 1120, minHeight: 700)
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
            defaultFilename: viewModel.exportFullHistory ? "traces-full-export.ics" : "traces-latest-import.ics"
        ) { result in
            switch result {
            case let .success(url):
                viewModel.status = "Exported \(viewModel.exportEvents.count) events to \(url.lastPathComponent)."
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
                            EventRow(event: event, compact: false)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                                        .fill(event.id == viewModel.selectedEventID ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: TracesTheme.cardCornerRadius)
                                        .stroke(event.id == viewModel.selectedEventID ? Color.accentColor.opacity(0.60) : TracesTheme.softBorder, lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(event.id == viewModel.selectedEventID ? 0.07 : 0.025), radius: 8, x: 0, y: 4)
                                .onTapGesture {
                                    if viewModel.selectedEventID == event.id {
                                        viewModel.selectedEventID = nil
                                    } else {
                                        viewModel.selectedEventID = event.id
                                    }
                                    viewModel.didSelectEventChanged()
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(spacing: 8) {
                    TracesBadge("\(viewModel.displayEvents.count) events", systemImage: "calendar", tint: .accentColor)
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
                systemImage: viewModel.exportFullHistory ? "tray.full" : "tray.and.arrow.up",
                tint: viewModel.exportFullHistory ? TracesTheme.warning : Color.accentColor
            )

            Spacer(minLength: 6)

            Toggle("Full export", isOn: $viewModel.exportFullHistory)
                .toggleStyle(.switch)
                .font(.caption)
                .help("Off: export latest import only. On: export all visible historical events.")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(TracesTheme.softBorder, lineWidth: 1))
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
