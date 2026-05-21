import Foundation

// MARK: - Incremental import merge
// Timeline JSON files can be partial exports. This service merges newly imported
// events into the current working session without deleting older events that are
// missing from the latest import file.

enum EventUpsertService {
    /// Result returned to the view model so the UI can show import statistics.
    struct Result {
        let events: [ICSEvent]
        let addedCount: Int
        let updatedCount: Int
    }

    /// Merges imported events into existing events using a stable upsert key.
    ///
    /// Behavior:
    /// - existing events are preserved by default
    /// - imported events with matching keys replace existing events
    /// - imported events with new keys are appended
    /// - final output is sorted by event start time for display/export
    static func merge(existing: [ICSEvent], imported: [ICSEvent]) -> Result {
        var mergedByKey: [String: ICSEvent] = [:]
        var orderKeys: [String] = []

        // Seed the merge dictionary with the current session.
        for event in existing {
            let key = eventUpsertKey(event)

            if mergedByKey[key] == nil {
                orderKeys.append(key)
            }

            mergedByKey[key] = event
        }

        var addedCount = 0
        var updatedCount = 0

        // Imported data wins for matching keys, but absence from the import does
        // not delete old historical events.
        for event in imported {
            let key = eventUpsertKey(event)

            if let old = mergedByKey[key] {
                if old != event {
                    updatedCount += 1
                }
            } else {
                orderKeys.append(key)
                addedCount += 1
            }

            mergedByKey[key] = event
        }

        let mergedEvents = orderKeys
            .compactMap { mergedByKey[$0] }
            .sorted {
                let lhsStart = $0.start ?? .distantPast
                let rhsStart = $1.start ?? .distantPast

                if lhsStart == rhsStart {
                    return $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
                }

                return lhsStart < rhsStart
            }

        return Result(
            events: mergedEvents,
            addedCount: addedCount,
            updatedCount: updatedCount
        )
    }

    /// Builds the identity key used for incremental import.
    ///
    /// The key combines location identity and minute-level start/end time buckets.
    /// Location identity prefers place ID, then coordinates, then text fallback.
    static func eventUpsertKey(_ event: ICSEvent) -> String {
        let startBucket = timeBucket(event.start)
        let endBucket = timeBucket(event.end)
        let locationKey = eventLocationKey(event)

        return "\(locationKey)|\(startBucket)|\(endBucket)"
    }

    /// Creates the strongest available location identity for an event.
    private static func eventLocationKey(_ event: ICSEvent) -> String {
        if let placeID = extractPlaceID(from: event) {
            return "placeID:\(placeID)"
        }

        if let lat = event.lat, let lon = event.lon {
            return "coord:\(roundedCoord(lat: lat, lon: lon))"
        }

        let normalizedLocation = normalizeForKey(event.location)
        let normalizedTitle = normalizeForKey(event.summary)

        if !normalizedLocation.isEmpty {
            return "location:\(normalizedLocation)"
        }

        return "title:\(normalizedTitle)"
    }

    /// Pulls a Google place ID from URL, description, or location fields.
    private static func extractPlaceID(from event: ICSEvent) -> String? {
        let combined = "\(event.url)\n\(event.description)\n\(event.location)"

        if let range = combined.range(of: "place_id:") {
            let suffix = combined[range.upperBound...]
            let placeID = suffix.prefix { char in
                char.isLetter || char.isNumber || char == "_" || char == "-"
            }

            let value = String(placeID)
            return value.isEmpty ? nil : value
        }

        if let range = combined.range(of: "Place ID:") {
            let suffix = combined[range.upperBound...]
            let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            let placeID = trimmed.prefix { char in
                char.isLetter || char.isNumber || char == "_" || char == "-"
            }

            let value = String(placeID)
            return value.isEmpty ? nil : value
        }

        return nil
    }

    /// Minute-level bucket reduces accidental duplicate keys caused by seconds.
    private static func timeBucket(_ date: Date?) -> String {
        guard let date else {
            return "no-time"
        }

        let seconds = Int(date.timeIntervalSince1970)
        let bucket = seconds / 60

        return String(bucket)
    }

    /// Coordinate fallback rounded to roughly meter-level precision.
    private static func roundedCoord(lat: Double, lon: Double) -> String {
        String(format: "%.5f,%.5f", lat, lon)
    }

    /// Normalizes text fallback keys so capitalization/extra whitespace do not
    /// create separate events.
    private static func normalizeForKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
