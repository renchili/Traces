# Code Map

This document maps each source file to the feature, view, or logic it controls.

## App shell

### `Traces/TracesApp.swift`

Controls:

- macOS app entry point
- initial window scene
- first `ContentView`

Do not add Timeline parsing, MapKit logic, or ICS export logic here.

## Top-level UI

### `Traces/ContentView.swift`

Controls:

- the three-pane app layout
- left event list column
- center map/detail split
- right timeline waterfall column
- import/export toolbar binding
- drag-and-drop file opening

Should contain:

- SwiftUI layout composition
- bindings from `TracesViewModel` to child views
- simple toolbar actions that call the view model

Should not contain:

- JSON parsing
- ICS encoding/decoding
- Google API calls
- MapKit delegate code
- conflict resolution algorithms
- event upsert logic

## Shared event UI

### `Traces/EventViews.swift`

Controls:

- `EventRow`: one row in the left event list
- `dateRange`: shared user-facing event date formatting

This file should stay small. Do not add map, timeline waterfall, or detail panel code here.

## Event detail and conflict UI

### `Traces/ConflictCandidatesView.swift`

Controls:

- `EventDetailView`: selected event detail panel
- `ConflictCandidatesView`: A/B/C conflict candidate review panel
- `CandidateRow`: clickable row for primary and suppressed candidates
- `primaryCandidateID`: sentinel ID used to represent the current primary/final event

User-facing behavior:

- A is the current final event
- B/C/etc are suppressed alternatives
- clicking A/B/C previews the candidate
- clicking “Use selected as final event” asks the view model to promote the selected candidate

Should not contain:

- MapKit code
- Timeline JSON parsing
- ICS export code
- direct mutation of the `events` array

## Map

### `Traces/EventMapView.swift`

Controls:

- `EventMapPanel`: map section header and container
- `EventMapView`: SwiftUI-to-AppKit MapKit bridge
- `TracesMapAnnotation`: single annotation type for event/candidate map markers
- map candidate selection callback
- map conflict lines between primary and suppressed candidates

Important rule:

- This is the only file that should use `MKMapView`, `MKAnnotation`, `MKPolyline`, or `MKMapViewDelegate`.

SwiftUI safety:

- Do not write SwiftUI bindings synchronously inside `updateNSView()`.
- Programmatic map selection must be guarded by `isApplyingSwiftUIUpdate`.
- User-driven map clicks may update bindings asynchronously on the main queue.

## Timeline waterfall

### `Traces/TimelineWaterfallView.swift`

Controls:

- `TimelineWaterfallView`: right-side timeline container
- `TimelineCanvas`: hour grid and event layout area
- `TimelineEventBlock`: one event block in the waterfall
- column assignment for overlapping timed events

Should not contain:

- import/export logic
- MapKit logic
- Google API calls
- final event promotion logic

## Settings

### `Traces/TimelineGeneratorSettingsView.swift`

Controls:

- Google API key input
- import window setting
- minimum stay setting
- home/aliased location filtering setting
- location cache count display
- cache clear action

Should only render settings and call closures/bindings supplied by the view model.

## View model

### `Traces/TracesViewModel.swift`

Controls:

- app state
- selected event
- selected conflict candidate
- file import actions
- ICS export action
- session restore/save/clear
- location cache clear/status
- final event promotion

This is the correct place for UI-triggered app actions. It should call service files rather than implementing parsing, API calls, or ICS encoding details inline.

## Timeline processing

### `Traces/TimelineProcessor.swift`

Controls:

- Google Timeline JSON decoding
- visit filtering
- unique location resolve request generation
- attaching resolved location data to visits
- impossible-overlap collapse
- adjacent visit merge
- conversion from visit data to `ICSEvent`

Should not contain SwiftUI views or view-model state.

## Incremental import

### `Traces/EventUpsertService.swift`

Controls:

- event upsert key generation
- merging imported events into existing events
- added/updated count calculation
- preserving events missing from a new partial import file

## Location resolution

### `Traces/GoogleLocationResolver.swift`

Controls:

- place ID and coordinate resolution
- Google Places / Geocoding endpoint calls
- resolver fallback behavior
- local cache reads/writes through `LocationCacheStore`

### `Traces/LocationCacheStore.swift`

Controls:

- local persistent location cache
- cache load/save/clear/count

## ICS

### `Traces/ICSCodec.swift`

Controls:

- `ICSWriter`: event list to `.ics`
- `ICSParser`: `.ics` preview into `ICSEvent`
- ICS escaping/unescaping
- line folding
- ICS date parsing
- `GEO` parsing/export

## Session

### `Traces/SessionStore.swift`

Controls:

- latest working session persistence
- manual JSON encode/decode of events and suppressed candidates
- restore of selected event, file name, generated ICS, and event list

## Template / currently unused workflow

### `Traces/Persistence.swift`

Xcode template persistence file. It is not part of the current Timeline JSON → ICS workflow unless explicitly integrated later.

## Tests

### `TracesTests/TracesTests.swift`

Placeholder unit test target.

Recommended future tests:

- Timeline JSON parsing
- conflict collapse
- event upsert merge
- candidate promotion
- ICS writer/parser round trip
- location cache behavior

### `TracesUITests/*`

Placeholder UI test target.

Recommended future tests:

- import JSON
- select event
- select conflict candidate
- promote candidate
- export ICS
