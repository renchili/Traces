# CHANGE.md

All notable changes to Traces are documented here.

This file follows the spirit of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): entries are grouped by version/date and by change type.

## [Unreleased]

### Planned

- Move Google API key storage from `UserDefaults` to Keychain or a backend resolver before any production distribution.
- Add unit tests for Timeline JSON parsing, event upsert keys, conflict promotion, and ICS export.
- Add sample Timeline JSON fixtures with redacted coordinates/place IDs.
- Add a user-visible location-resolution status panel for cache hits, API hits, and fallbacks.

## [0.4.0] - 2026-05-21

### Added

- Added documentation for the current codebase:
  - `docs/ARCHITECTURE.md` explains the app architecture, data flow, and file ownership.
  - `docs/FEATURES.md` explains supported user-facing features and expected behavior.
  - `docs/CODE_MAP.md` maps each Swift file to the feature/view it controls.
- Split the previously oversized `EventViews.swift` into focused files:
  - `EventViews.swift` now only contains `EventRow` and shared event date formatting.
  - `ConflictCandidatesView.swift` contains event details and A/B/C conflict candidate UI.
  - `EventMapView.swift` contains the MapKit bridge, map annotations, and conflict lines.
  - `TimelineWaterfallView.swift` contains the right-side timeline waterfall and event-block layout.
- Added `TracesMapAnnotation` as the single map annotation type to avoid duplicate `EventAnnotation` declarations.

### Changed

- Refactored view code so each file has one main responsibility.
- Reduced ambiguous type lookup risk by removing duplicate map annotation definitions.
- Kept `ContentView` as the top-level three-pane layout shell instead of a business-logic container.

### Fixed

- Fixed `EventAnnotation is ambiguous for type lookup` caused by duplicate class declarations.
- Fixed invalid redeclaration of `EventAnnotation`.
- Reduced future risk of MapKit delegate/view code being mixed with timeline and event detail rendering.

## [0.3.0] - 2026-05-21

### Added

- Added conflict candidate selection and final-event replacement.
- Added `promoteSelectedConflictCandidate()` in `TracesViewModel`.
- Added support for replacing the final generated event location with a selected suppressed candidate.
- Added manual replacement notes into the event description after a candidate is promoted.
- Added logic to keep the old primary event as a suppressed candidate after promotion, allowing users to switch back.

### Changed

- Selecting A/B/C now previews candidates, while using the explicit “Use selected as final event” action changes the final event.
- Regenerates ICS after conflict-candidate promotion so export reflects the chosen final event.

### Fixed

- Fixed accidental local constant assignment in `promoteSelectedConflictCandidate()`.
- Fixed confusing behavior where selecting a candidate looked like it might change the final event but did not.

## [0.2.0] - 2026-05-21

### Added

- Added location conflict detection for impossible overlapping location candidates.
- Added suppressed candidate storage on `ICSEvent`.
- Added A/B/C conflict candidate UI with selected-state highlighting.
- Added candidate distance display when both locations have coordinates.
- Added map display for selected events and conflict candidates.
- Added map lines between the primary event location and suppressed candidates.
- Added latitude/longitude support to `ICSEvent`.
- Added `GEO` export support in generated ICS files.
- Added persistent session restore.
- Added local persistent caching for resolved Google place IDs.
- Added cache-aware Google resolver flow:
  - memory cache
  - local `UserDefaults` cache
  - Google Places API New
  - Google Places API Legacy
  - Geocoding by place ID
  - reverse geocoding by coordinates
  - coordinate/place ID fallback

### Changed

- Changed conflict details from plain description text to structured UI.
- Changed selected event map behavior to focus on selected event candidates.
- Changed session storage schema to include suppressed conflict candidates.
- Changed model initializers to `nonisolated` to satisfy Swift 6 concurrency checks.
- Changed macOS MapKit delegate selection handling to use the macOS `didSelect view` signature.

### Fixed

- Fixed duplicated or impossible same-time events such as one user appearing in two different places at the same time.
- Fixed `Publishing changes from within view updates is not allowed` by avoiding binding writes during MapKit-driven SwiftUI view updates.
- Fixed macOS MapKit delegate error: `Cannot override 'mapView' which has been marked unavailable`.
- Fixed `MKPolyline` coordinate initialization for macOS.
- Fixed missing `suppressedCandidates` initializer argument after extending `ICSEvent`.
- Fixed Swift 6 actor-isolation warnings in session decoding/encoding paths.

## [0.1.0] - 2026-05-21

### Added

- Added initial standalone macOS SwiftUI app structure.
- Added three-pane layout:
  - left panel for event list, import/export actions, search, and status
  - center panel with map preview and event details
  - right panel with timeline waterfall visualization
- Added ICS preview support.
- Added Timeline JSON import support.
- Added Timeline JSON to ICS generation.
- Added `TracesViewModel` to move state and app actions out of `ContentView`.
- Added `EventUpsertService` for event merge/upsert logic.
- Added incremental Timeline JSON import behavior:
  - importing a new Timeline JSON no longer clears existing events
  - existing events are updated by upsert key
  - new events are appended
  - missing historical events are preserved

### Changed

- Changed Timeline JSON import from full replacement to incremental merge.
- Changed timeline waterfall rendering to support overlapping event columns.
- Changed timeline waterfall layout to recalculate on split-view width changes.
- Changed `ICSEvent` equality to include all visible/exported event fields.

### Fixed

- Fixed event loss when importing a partial Timeline JSON file.
- Fixed overlapping event blocks in the timeline waterfall.
- Fixed timeline waterfall not refreshing correctly after split-view drag resizing.
- Fixed event text compression in narrow timeline columns.
- Fixed UI layout where side panels did not align to the top in the split view.
- Fixed app state being lost after restart by adding session persistence.

## Notes

- Existing old sessions may not contain newer conflict candidate fields. Clearing the last session and re-importing Timeline JSON is recommended after schema-changing updates.
- Timeline JSON import is additive by default. Use “Clear Last Session” only when intentionally resetting the working event set.
