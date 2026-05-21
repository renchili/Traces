# Traces Features

Traces is a macOS app for turning Google Timeline exports into inspectable and editable calendar events.

## 1. Open ICS preview

Users can open an existing `.ics` file to preview events without importing them into Apple Calendar.

Supported preview data:

- event title
- event start/end time
- location text
- description text
- URL
- `GEO` latitude/longitude when present

## 2. Import Google Timeline JSON

Users can import Google Timeline JSON directly.

The app reads Timeline visits, filters short stays, resolves place names, and creates calendar-like events.

Current import controls:

- `Last N days`: limits import window relative to the latest timestamp in the JSON file.
- `Min stay minutes`: ignores very short visits.
- `Remove Home/Aliased over N minutes`: filters long home-like stays from generated events.
- Google API key: optional key used for place ID / coordinate resolution.

## 3. Incremental import

Timeline JSON import is incremental, not destructive.

When a new JSON file is imported:

- new events are added
- matching existing events are updated
- old events not present in the new file are preserved

This protects historical events when the imported JSON file only covers a partial date range.

## 4. Local location cache

Resolved place IDs and coordinates are cached locally.

Behavior:

- already resolved place IDs are loaded from local cache
- new place IDs are resolved only once
- cache can be cleared from settings
- cache count is visible in the settings popover

This reduces repeated Google API calls and keeps repeated imports faster.

## 5. Event list and search

The left panel shows generated or loaded events.

Users can:

- select an event
- search by title
- search by location
- search by description
- see import/export status
- clear the last session

## 6. Map preview

The center top panel shows event locations on an Apple MapKit map.

For normal events, the map focuses on the selected event.

For conflict events, the map shows:

- A: current final/primary event location
- B/C/etc: suppressed conflict candidates
- lines from A to each suppressed candidate
- highlighted line/marker for the selected conflict candidate

## 7. Event detail panel

The center bottom panel shows details for the selected event:

- title
- date range
- location
- coordinates
- Google Maps URL
- generated description
- conflict candidate warning when applicable

## 8. Conflict candidate review

Google Timeline can report multiple overlapping visits that cannot all be correct. Traces detects this and keeps alternate candidates for review.

The conflict UI shows:

- A = current final event
- B/C/etc = suppressed candidates
- distance from A when both locations have coordinates
- selected state for previewed candidate

Selecting a candidate only previews it. The final exported event changes only after the user clicks:

```text
Use selected as final event
```

After promotion:

- selected candidate becomes the event title/location/coordinate/URL
- old A becomes a suppressed candidate
- generated ICS is refreshed
- session is saved

## 9. Timeline waterfall

The right panel shows timed events as vertical blocks.

Features:

- hour grid
- selected event highlighting
- overlapping event column layout
- compact title display in narrow columns
- width-based recalculation when the split view is resized

## 10. Export ICS

Users can export the current final event list to `.ics`.

Export includes:

- `UID`
- `DTSTAMP`
- `DTSTART`
- `DTEND`
- `SUMMARY`
- `LOCATION`
- `DESCRIPTION`
- `URL`
- `GEO` when coordinates are available

Conflict candidates are not exported as separate events. Only the current final event is exported.

## 11. Session restore

The app restores the last working session on launch.

Restored data includes:

- event list
- selected event ID
- generated ICS text
- last file name

Use “Clear Last Session” to reset the current working set.

## 12. Current limitations

- The Google API key is stored in development settings; production distribution should use Keychain or a backend proxy.
- There are no automated unit tests yet.
- Conflict resolution is heuristic and should remain reviewable by the user.
- Google Timeline JSON shape can change; parsing should be tested against real redacted samples.
