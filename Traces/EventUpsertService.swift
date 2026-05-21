import Foundation

enum EventUpsertService {
    struct Result {
        let events: [ICSEvent]
        let addedCount: Int
        let updatedCount: Int
    }

    static func merge(existing: [ICSEvent], imported: [ICSEvent]) -> Result {
        var mergedByKey: [String: ICSEvent] = [:]
        var orderKeys: [String] = []

        for event in existing {
            let key = eventUpsertKey(event)

            if mergedByKey[key] == nil {
                orderKeys.append(key)
            }

            mergedByKey[key] = event
        }

        var addedCount = 0
        var updatedCount = 0

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

    static func eventUpsertKey(_ event: ICSEvent) -> String {
        let startBucket = timeBucket(event.start)
        let endBucket = timeBucket(event.end)
        let locationKey = eventLocationKey(event)

        return "\(locationKey)|\(startBucket)|\(endBucket)"
    }

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

    private static func timeBucket(_ date: Date?) -> String {
        guard let date else {
            return "no-time"
        }

        let seconds = Int(date.timeIntervalSince1970)
        let bucket = seconds / 60

        return String(bucket)
    }

    private static func roundedCoord(lat: Double, lon: Double) -> String {
        String(format: "%.5f,%.5f", lat, lon)
    }

    private static func normalizeForKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
