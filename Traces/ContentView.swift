import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Foundation

// MARK: - Top-level app shell
// ContentView owns only the window layout and high-level bindings.
// Business logic lives in TracesViewModel; map/timeline/detail rendering lives
// in dedicated child view files.

struct ContentView: View {
    // Single source of UI state for the current window.
    @StateObject private var viewModel = TracesViewModel()

    var body: some View {
        HSplitView {
            // Left: import controls, search, and event list.
            leftEventList
                .frame(minWidth: 240, idealWidth: 340, maxWidth: 480)
                .frame(maxHeight: .infinity, alignment: .top)

            // Center: map on top, selected event detail below.
            middleMapAndDetail
                .frame(minWidth: 460, idealWidth: 760)
                .frame(maxHeight: .infinity, alignment: .top)

            // Right: time-based waterfall overview.
            rightTimelineWaterfall
                .frame(minWidth: 240, idealWidth: 320, maxWidth: 460)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 1100, minHeight: 680)
        .background(.background)
        .onAppear {
            viewModel.onAppear()
        }
        // Drag-and-drop file opening. The actual file handling is delegated to
        // the view model so this view stays as layout-only as possible.
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

    // MARK: - Left event list column

    private var leftEventList: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            TextField("Search events", text: $viewModel.query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 6)
            }

            if !viewModel.status.isEmpty {
                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            // Custom list instead of SwiftUI List selection because macOS List
            // does not toggle nil when clicking an already-selected row.
            // Required behavior: click event once to select, click the same event
            // again to clear selection and return the map to all-events mode.
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.filteredEvents) { event in
                        EventRow(event: event, compact: false)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(event.id == viewModel.selectedEventID ? Color.accentColor.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(event.id == viewModel.selectedEventID ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
                            )
                            .padding(.horizontal, 8)
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
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Text("\(viewModel.filteredEvents.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                Text(viewModel.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }

    // MARK: - Toolbar

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
            .buttonStyle(.bordered)

            Button {
                viewModel.showingGeneratorSettings.toggle()
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
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
                viewModel.exportICS()
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.events.isEmpty)
        }
    }

    // MARK: - Center map and event detail column

    private var middleMapAndDetail: some View {
        VSplitView {
            EventMapPanel(
                events: viewModel.filteredEvents,
                selectedEventID: $viewModel.selectedEventID,
                selectedConflictCandidateID: $viewModel.selectedConflictCandidateID
            )
            .frame(minHeight: 260, idealHeight: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }

    // MARK: - Right timeline waterfall column

    private var rightTimelineWaterfall: some View {
        TimelineWaterfallView(
            events: viewModel.filteredEvents,
            selectedEventID: $viewModel.selectedEventID
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
    }
}
