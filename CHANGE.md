# CHANGE.md

## Unreleased

### Added

- Added a three-pane macOS layout:
  - left panel for event list and search
  - center panel split into map preview and event details
  - right panel for timeline waterfall visualization
- Added Timeline JSON incremental import behavior.
  - Importing a new Timeline JSON no longer clears existing events.
  - Existing events are updated by upsert key.
  - New events are appended.
  - Missing historical events are preserved.
- Added `TracesViewModel` to move UI state and user actions out of `ContentView`.
- Added `EventUpsertService` for event merge / upsert logic.
- Added persistent session restore.
  - Restores last events
  - Restores selected event
  - Restores generated ICS content
  - Restores last file name
- Added location conflict detection for impossible overlapping location candidates.
  - Same-time or highly overlapping visits are collapsed into one primary event.
  - Suppressed candidates are retained for debugging.
  - Candidate distance from the primary event is calculated when coordinates are available.
- Added conflict candidate display in event details.
  - Shows A/B/C candidates.
  - Highlights the selected candidate.
  - Shows distance between primary and suppressed candidates.
- Added map display for selected event conflicts.
  - Shows primary location and suppressed candidates.
  - Draws conflict distance lines.
  - Supports selecting conflict candidates from the detail panel and map.
- Added latitude / longitude support to `ICSEvent`.
- Added suppressed candidate model data to `ICSEvent`.
- Added GEO export support in generated ICS files.
- Added local persistent caching for resolved Google place IDs.
- Added cache-aware Google location resolver flow.
  - Memory cache
  - UserDefaults-backed local cache
  - Google Places API New
  - Google Places API Legacy
  - Geocoding by place ID
  - Reverse geocoding by coordinates
  - Coordinate / place ID fallback

### Changed

- Refactored `ContentView` to focus on rendering and bindings only.
- Moved import, export, session, cache, and merge actions into `TracesViewModel`.
- Moved incremental merge and upsert key logic into `EventUpsertService`.
- Changed Timeline JSON import from full replacement to incremental merge.
- Changed timeline waterfall rendering to support overlapping event columns.
- Changed timeline waterfall layout to recalculate on split-view width changes.
- Changed selected event map behavior to focus on selected event candidates.
- Changed conflict details from plain description text to structured UI.
- Changed session storage schema to include suppressed conflict candidates.
- Changed `ICSEvent` equality to include all visible and exported event fields.
- Changed model initializers to be `nonisolated` to satisfy Swift 6 concurrency checks.
- Changed macOS MapKit delegate selection handling to use the macOS `didSelect view` signature.

### Fixed

- Fixed duplicated / impossible same-time events such as one user appearing at two different places at the same time.
- Fixed overlapping event blocks in the timeline waterfall.
- Fixed timeline waterfall not refreshing correctly after split-view drag resizing.
- Fixed event text compression in narrow timeline columns.
- Fixed Swift 6 actor-isolation warnings in session decoding / encoding paths.
- Fixed missing `suppressedCandidates` initializer argument after extending `ICSEvent`.
- Fixed macOS MapKit delegate method error:
  - `Cannot override 'mapView' which has been marked unavailable`
- Fixed `MKPolyline` coordinate initialization for macOS.
- Fixed session restore after adding latitude / longitude and conflict candidate data.
- Fixed UI layout where side panels did not align to the top in the split view.
- Fixed app state being lost after restart by adding session persistence.

### Notes

- Existing old sessions may not contain new conflict candidate fields. Clearing the last session and re-importing Timeline JSON is recommended after this change.
- Google API keys are still stored through app settings / UserDefaults in the development build. A production release should move API keys to Keychain or a backend resolver.
- Timeline JSON import is now additive. Use “Clear Last Session” only when intentionally resetting the working event set.
