import Foundation

final class TimelineProcessor {
    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private struct Visit: Sendable {
        var start: Date
        var end: Date
        var semanticType: String
        var placeID: String
        var lat: Double?
        var lon: Double?
        var sourceCount: Int
        var resolved: ResolvedLocation?
    }

    static func generateEvents(
        from jsonData: Data,
        options: TimelineOptions,
        apiKey: String
    ) async throws -> [ICSEvent] {
        var visits = try parseVisits(from: jsonData, options: options)

        let requests = buildUniqueResolveRequests(from: visits)
        let resolver = GoogleLocationResolver(apiKey: apiKey)
        let resolvedMap = await resolver.resolveAll(requests)

        for index in visits.indices {
            let key = LocationResolveRequest.cacheKey(
                placeID: visits[index].placeID,
                lat: visits[index].lat,
                lon: visits[index].lon
            )
            visits[index].resolved = resolvedMap[key]
        }

        let merged = mergeVisits(visits, options: options)

        return merged.map { visit in
            makeEvent(from: visit)
        }
    }

    private static func parseVisits(from jsonData: Data, options: TimelineOptions) throws -> [Visit] {
        let entries = try JSONDecoder().decode([TimelineEntry].self, from: jsonData)

        let allEndDates = entries.compactMap { parseDate($0.endTime) }
        guard let maxTime = allEndDates.max() else { return [] }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -options.lastDays,
            to: maxTime
        ) ?? maxTime

        var visits: [Visit] = []

        for entry in entries {
            guard
                entry.visit != nil,
                let start = parseDate(entry.startTime),
                let end = parseDate(entry.endTime),
                end >= cutoff
            else {
                continue
            }

            let durationMinutes = end.timeIntervalSince(start) / 60.0
            guard durationMinutes > options.minStayMinutes else { continue }

            let candidate = entry.visit?.topCandidate
            let semantic = candidate?.semanticType ?? "Unknown"
            let placeID = candidate?.placeID ?? ""
            let coord = parseGeo(candidate?.placeLocation)

            if isHomeLike(semantic) && durationMinutes > options.removeHomeOverMinutes {
                continue
            }

            visits.append(
                Visit(
                    start: start,
                    end: end,
                    semanticType: semantic,
                    placeID: placeID,
                    lat: coord?.lat,
                    lon: coord?.lon,
                    sourceCount: 1,
                    resolved: nil
                )
            )
        }

        return visits.sorted { $0.start < $1.start }
    }

    private static func buildUniqueResolveRequests(from visits: [Visit]) -> [LocationResolveRequest] {
        var result: [String: LocationResolveRequest] = [:]

        for visit in visits {
            let request = LocationResolveRequest.make(
                placeID: visit.placeID,
                lat: visit.lat,
                lon: visit.lon
            )

            result[request.cacheKey] = request
        }

        return Array(result.values)
    }

    private static func mergeVisits(_ visits: [Visit], options: TimelineOptions) -> [Visit] {
        var merged: [Visit] = []

        for visit in visits {
            guard var last = merged.popLast() else {
                merged.append(visit)
                continue
            }

            let rawGapMinutes = visit.start.timeIntervalSince(last.end) / 60.0
            let effectiveGapMinutes = max(0, rawGapMinutes)
            let isOverlapping = rawGapMinutes <= 0

            let sameResolvedPlace =
                visit.resolved?.mergeKey == last.resolved?.mergeKey

            let closeLocal = distanceMeters(
                lat1: last.lat,
                lon1: last.lon,
                lat2: visit.lat,
                lon2: visit.lon
            ) <= options.localMergeDistanceMeters

            let shouldMerge =
                (isOverlapping || effectiveGapMinutes <= options.localMergeGapMinutes)
                && (sameResolvedPlace || closeLocal)

            if shouldMerge {
                last.start = min(last.start, visit.start)
                last.end = max(last.end, visit.end)
                last.sourceCount += visit.sourceCount

                if last.resolved == nil {
                    last.resolved = visit.resolved
                }

                merged.append(last)
            } else {
                merged.append(last)
                merged.append(visit)
            }
        }

        return merged
    }

    private static func makeEvent(from visit: Visit) -> ICSEvent {
        let resolved = visit.resolved
        let coordText = coordinateText(visit)
        let url = resolved?.url ?? mapsURL(visit)
        let duration = Int(round(visit.end.timeIntervalSince(visit.start) / 60.0))
        let title = title(for: visit)

        let description = """
        Google Timeline
        Duration: \(duration) minutes
        Merged visits: \(visit.sourceCount)
        Original semantic type: \(visit.semanticType)
        Place ID: \(visit.placeID)
        Resolver source: \(resolved?.source ?? "none")
        Resolver confidence: \(String(format: "%.2f", resolved?.confidence ?? 0))
        Resolver debug: \(resolved?.debugMessage ?? "")
        \(url.isEmpty ? "" : "Google Maps: \(url)")
        """

        return ICSEvent(
            id: stableUID(visit: visit, title: title),
            summary: title,
            location: resolved?.subtitle.isEmpty == false ? resolved!.subtitle : coordText,
            description: description,
            url: url,
            start: visit.start,
            end: visit.end
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        return isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatterNoFractionalSeconds.date(from: value)
    }

    private static func parseGeo(_ value: String?) -> (lat: Double, lon: Double)? {
        guard let value, value.hasPrefix("geo:") else { return nil }

        let pair = value.dropFirst(4).split(separator: ",")
        guard
            pair.count == 2,
            let lat = Double(pair[0]),
            let lon = Double(pair[1])
        else {
            return nil
        }

        return (lat, lon)
    }

    private static func isHomeLike(_ semantic: String) -> Bool {
        semantic.lowercased().contains("home")
    }

    private static func title(for visit: Visit) -> String {
        if let title = visit.resolved?.title.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        let coord = coordinateText(visit)

        if !coord.isEmpty {
            return "Location \(coord)"
        }

        if visit.semanticType != "Aliased Location" && visit.semanticType != "Unknown" {
            return visit.semanticType
        }

        return "Timeline Location"
    }

    private static func coordinateText(_ visit: Visit) -> String {
        guard let lat = visit.lat, let lon = visit.lon else { return "" }
        return String(format: "%.6f,%.6f", lat, lon)
    }

    private static func mapsURL(_ visit: Visit) -> String {
        if !visit.placeID.isEmpty {
            return "https://www.google.com/maps/place/?q=place_id:\(visit.placeID)"
        }

        guard let lat = visit.lat, let lon = visit.lon else { return "" }

        return String(
            format: "https://www.google.com/maps/search/?api=1&query=%.7f,%.7f",
            lat,
            lon
        )
    }

    private static func stableUID(visit: Visit, title: String) -> String {
        let mergeKey = visit.resolved?.mergeKey ?? visit.placeID
        let raw = "\(visit.start.timeIntervalSince1970)|\(visit.end.timeIntervalSince1970)|\(title)|\(mergeKey)"
        let encoded = Data(raw.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        return "\(encoded)@traces-timeline"
    }

    private static func distanceMeters(
        lat1: Double?,
        lon1: Double?,
        lat2: Double?,
        lon2: Double?
    ) -> Double {
        guard let lat1, let lon1, let lat2, let lon2 else { return .infinity }

        return distanceMeters(
            lat1: lat1,
            lon1: lon1,
            lat2: lat2,
            lon2: lon2
        )
    }

    private static func distanceMeters(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180

        let a =
            sin(dp / 2) * sin(dp / 2)
            + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)

        return 2 * r * asin(sqrt(a))
    }
}
