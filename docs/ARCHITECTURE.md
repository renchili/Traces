# Traces Architecture

Traces is a standalone macOS SwiftUI app for previewing, cleaning, and exporting Google Timeline location data as calendar events.

The app is intentionally split into small files. Each file owns one layer or one view area so that MapKit, timeline layout, conflict resolution, persistence, and ICS encoding do not become mixed together again.

## High-level data flow

```text
User opens Timeline JSON or ICS
        ↓
TracesViewModel receives the file action
        ↓
TimelineProcessor parses Google Timeline JSON into visits
        ↓
GoogleLocationResolver resolves place IDs / coordinates
        ↓
TimelineProcessor collapses impossible overlapping candidates
        ↓
EventUpsertService merges imported events into existing session events
        ↓
SwiftUI views render list / map / detail / waterfall
        ↓
User optionally promotes a conflict candidate as the final event
        ↓
ICSWriter exports final ICSEvent list
```

## UI layout

```text
ContentView
├── Left column
│   ├── toolbar
│   ├── search field
│   ├── import/export status
│   └── EventRow list
│
├── Center column
│   ├── EventMapPanel / EventMapView
│   └── EventDetailView / ConflictCandidatesView
│
└── Right column
    └── TimelineWaterfallView / TimelineCanvas / TimelineEventBlock
```

## Layers

### 1. App entry

| File | Responsibility |
| --- | --- |
| `TracesApp.swift` | macOS app entry point. Creates the first `ContentView`. |

### 2. Models

| File | Responsibility |
| --- | --- |
| `Models.swift` | Shared value models: `ICSEvent`, `SuppressedCandidate`, Timeline JSON DTOs, `TimelineOptions`, `ResolvedLocation`, and `LocationResolveRequest`. |

Models are deliberately kept as plain Swift structs. They should not open files, call APIs, render SwiftUI, or mutate app state.

### 3. View model / app actions

| File | Responsibility |
| --- | --- |
| `TracesViewModel.swift` | Main `ObservableObject`. Owns app state, selected event, selected conflict candidate, import/export actions, session restore, cache clearing, and final-event promotion. |

`TracesViewModel` is the bridge between UI and services. It is allowed to call services, update published state, and trigger persistence. It should not contain SwiftUI layout code.

### 4. Timeline import and processing

| File | Responsibility |
| --- | --- |
| `TimelineProcessor.swift` | Converts Google Timeline JSON into `ICSEvent` values. Parses visits, resolves locations, collapses impossible overlaps, merges adjacent visits, and creates final event descriptions. |
| `EventUpsertService.swift` | Incrementally merges imported events into the current event list so partial imports do not delete history. |

### 5. Location resolution and cache

| File | Responsibility |
| --- | --- |
| `GoogleLocationResolver.swift` | Resolves Google place IDs or coordinates into human-readable names and map URLs. Uses local cache first, then Google endpoints, then fallback. |
| `LocationCacheStore.swift` | Stores resolved locations locally so already-seen place IDs are not looked up again. |

### 6. ICS import/export

| File | Responsibility |
| --- | --- |
| `ICSCodec.swift` | Reads `.ics` preview files and writes generated calendar events. Owns ICS escaping, folding, date parsing, and `GEO` export. |

### 7. Persistence

| File | Responsibility |
| --- | --- |
| `SessionStore.swift` | Saves and restores the latest working session. Uses a manual JSON codec to avoid Swift 6 actor-isolation issues with direct `Codable` use inside an actor. |
| `Persistence.swift` | Xcode template persistence file, currently not part of the Timeline/ICS workflow unless explicitly used later. |

### 8. SwiftUI views

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | Top-level three-pane shell. Owns layout and binds view model state into child views. |
| `EventViews.swift` | Small shared event UI: `EventRow` and `dateRange`. |
| `ConflictCandidatesView.swift` | Event detail panel and A/B/C conflict candidate chooser. |
| `EventMapView.swift` | Map panel, MapKit bridge, map annotations, and conflict candidate lines. |
| `TimelineWaterfallView.swift` | Right-side timeline waterfall view and event block layout. |
| `TimelineGeneratorSettingsView.swift` | Settings popover for Google API key, import window, minimum stay time, home filtering, and cache actions. |

## Conflict candidate model

When Google Timeline reports overlapping visits that cannot all be true, Traces keeps one event as the primary event and stores the others in `suppressedCandidates`.

```text
ICSEvent
├── summary/location/lat/lon = current final event
└── suppressedCandidates[] = alternate candidates that occurred at the same or overlapping time
```

A user can select B/C in the conflict UI to preview it on the map. The final event is changed only when the user clicks “Use selected as final event”.

## Incremental import behavior

Timeline JSON import is additive:

```text
existing session events
        +
new imported events
        ↓
EventUpsertService.merge(...)
        ↓
updated session events
```

This avoids deleting old events when a newly imported Timeline JSON file covers only a partial date range.

## MapKit notes

`EventMapView` is the only file that should use `MKMapView`, `MKAnnotation`, `MKPolyline`, or `MKMapViewDelegate`.

Do not place MapKit delegate methods in `ContentView`, `EventDetailView`, or timeline views.

The MapKit bridge must avoid writing SwiftUI bindings during `updateNSView()`. Programmatic annotation selection should be guarded with `isApplyingSwiftUIUpdate`; user clicks can update bindings asynchronously on the main queue.

## File ownership rules

- UI layout belongs in SwiftUI view files.
- App actions and state belong in `TracesViewModel`.
- Timeline parsing belongs in `TimelineProcessor`.
- Incremental merge belongs in `EventUpsertService`.
- Google API and cache logic belong in resolver/cache files.
- ICS details belong in `ICSCodec`.
- MapKit details belong only in `EventMapView`.
- Timeline waterfall layout belongs only in `TimelineWaterfallView`.

## Build note

The Xcode project uses a file-system synchronized root group for the `Traces` folder, so newly added Swift files under `Traces/` are automatically included by Xcode.
