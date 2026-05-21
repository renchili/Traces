import Foundation

// MARK: - Google Timeline JSON processor
// Converts Google Timeline visit data into final ICSEvent values.
// This file owns parsing, filtering, place resolution attachment, impossible
// overlap collapse, local visit merging, and event construction.

final class TimelineProcessor {
    // Google Timeline timestamps can appear with or without fractional seconds.
    // Keep both formatters so parsing does not fail on mixed exports.
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

    /// Internal normalized visit representation used before creating ICSEvent.
    ///
    /// A Timeline visit may later be resolved, collapsed with overlapping visits,
    /// or merged with nearby visits. Keeping this separate from ICSEvent avoids
    /// leaking parsing/intermediate state into exported calendar data.
    private struct Visit: Sendable {
        var start: Date
        var end: Date
        var semanticType: String
        var placeID: String
        var lat: Double?
        var lon: Double?
        var sourceCount: Int
        var resolved: ResolvedLocation?
        var suppressedCandidates: [SuppressedCandidate]
    }

    /// Public entry point used by TracesViewModel.
    ///
    /// Pipeline:
    /// 1. Parse Timeline JSON visits.
    /// 2. Build unique place/coordinate resolve requests.
    /// 3. Attach resolved names/URLs to visits.
    /// 4. Collapse impossible same-time overlaps into one primary + candidates.
    /// 5. Merge adjacent visits at the same place.
    /// 6. Convert visits into final ICSEvent values.
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

        visits = collapseImpossibleOverlaps(visits)

        let merged = mergeVisits(visits, options: options)

        return merged.map { visit in
            makeEvent(from: visit)
        }
    }

    /// Decodes Timeline JSON and applies basic import filters.
    ///
    /// Filters:
    /// - only visit entries are used
    /// - events outside the configured last-N-days window are skipped
    /// - short stays are skipped
    /// - long home-like stays are skipped
    private static func parseVisits(from jsonData: Data, options: TimelineOptions) throws -> [Visit] {
        let entries = try JSONDecoder().decode([TimelineEntry].self, from: jsonData)

        // Use the newest timestamp in the export as the reference point. This is
        // safer than system time because users may import historical exports.
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
                    resolved: nil,
                    suppressedCandidates: []
                )
            )
        }

        return visits.sorted { $0.start < $1.start }
    }

    /// Deduplicates resolver requests so one place ID/coordinate is looked up once.
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

    /// Collapses impossible overlaps. A person cannot be in two far-apart places
    /// at the same time, so the lower-quality visit becomes a suppressed
    /// candidate attached to the winner.
    private static func collapseImpossibleOverlaps(_ visits: [Visit]) -> [Visit] {
        let sorted = visits.sorted {
            if $0.start == $1.start {
                return $0.end < $1.end
            }

            return $0.start < $1.start
        }

        var result: [Visit] = []

        for visit in sorted {
            guard let last = result.popLast() else {
                result.append(visit)
                continue
            }

            if shouldCollapseConflict(last, visit) {
                let winner = betterVisit(last, visit)
                let loser = isSameVisit(winner, last) ? visit : last

                var collapsed = winner
                collapsed.start = min(last.start, visit.start)
                collapsed.end = max(last.end, visit.end)
                collapsed.sourceCount = last.sourceCount + visit.sourceCount

                let loserCandidate = makeSuppressedCandidate(
                    loser: loser,
                    primary: winner
                )

                collapsed.suppressedCandidates.append(loserCandidate)
                collapsed.suppressedCandidates.append(contentsOf: last.suppressedCandidates)
                collapsed.suppressedCandidates.append(contentsOf: visit.suppressedCandidates)
                collapsed.suppressedCandidates = dedupeSuppressedCandidates(collapsed.suppressedCandidates)

                result.append(collapsed)
            } else {
                result.append(last)
                result.append(visit)
            }
        }

        return result
    }

    /// Converts a losing overlapping visit into a user-reviewable candidate.
    private static func makeSuppressedCandidate(
        loser: Visit,
        primary: Visit
    ) -> SuppressedCandidate {
        let distance: Double?

        if let primaryLat = primary.lat,
           let primaryLon = primary.lon,
           let loserLat = loser.lat,
           let loserLon = loser.lon {
            distance = distanceMeters(
                lat1: primaryLat,
                lon1: primaryLon,
                lat2: loserLat,
                lon2: loserLon
            )
        } else {
            distance = nil
        }

        return SuppressedCandidate.make(
            title: title(for: loser),
            placeID: loser.placeID,
            lat: loser.lat,
            lon: loser.lon,
            start: loser.start,
            end: loser.end,
            distanceMetersFromPrimary: distance
        )
    }

    /// Removes duplicate suppressed candidates after repeated collapse/merge steps.
    private static func dedupeSuppressedCandidates(_ candidates: [SuppressedCandidate]) -> [SuppressedCandidate] {
        var seen: Set<String> = []
        var result: [SuppressedCandidate] = []

        for candidate in candidates {
            let key = "\(candidate.title)|\(candidate.placeID)|\(candidate.lat ?? 0)|\(candidate.lon ?? 0)|\(candidate.start?.timeIntervalSince1970 ?? 0)|\(candidate.end?.timeIntervalSince1970 ?? 0)"

            if !seen.contains(key) {
                seen.insert(key)
                result.append(candidate)
            }
        }

        return result
    }

    private static func isSameVisit(_ lhs: Visit, _ rhs: Visit) -> Bool {
        lhs.placeID == rhs.placeID
            && lhs.start == rhs.start
            && lhs.end == rhs.end
            && lhs.lat == rhs.lat
            && lhs.lon == rhs.lon
    }

    /// Conflict heuristic: same/near-same time windows or large overlap ratio.
    private static func shouldCollapseConflict(_ lhs: Visit, _ rhs: Visit) -> Bool {
        let overlap = overlapSeconds(lhs, rhs)
        guard overlap > 0 else { return false }

        let lhsDuration = max(1, lhs.end.timeIntervalSince(lhs.start))
        let rhsDuration = max(1, rhs.end.timeIntervalSince(rhs.start))
        let shorterDuration = min(lhsDuration, rhsDuration)
        let overlapRatio = overlap / shorterDuration

        let startsAlmostSame = abs(lhs.start.timeIntervalSince(rhs.start)) <= 120
        let endsAlmostSame = abs(lhs.end.timeIntervalSince(rhs.end)) <= 120

        if startsAlmostSame && endsAlmostSame {
            return true
        }

        if overlapRatio >= 0.75 {
            return true
        }

        return false
    }

    private static func overlapSeconds(_ lhs: Visit, _ rhs: Visit) -> TimeInterval {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        return max(0, end.timeIntervalSince(start))
    }

    /// Chooses the primary visit when two visits conflict.
    private static func betterVisit(_ lhs: Visit, _ rhs: Visit) -> Visit {
        let lhsScore = visitQualityScore(lhs)
        let rhsScore = visitQualityScore(rhs)

        if lhsScore == rhsScore {
            let lhsDuration = lhs.end.timeIntervalSince(lhs.start)
            let rhsDuration = rhs.end.timeIntervalSince(rhs.start)

            if lhsDuration == rhsDuration {
                return lhs.start <= rhs.start ? lhs : rhs
            }

            return lhsDuration >= rhsDuration ? lhs : rhs
        }

        return lhsScore >= rhsScore ? lhs : rhs
    }

    /// Scores visit quality for conflict collapse. Resolved Google names and
    /// place IDs are preferred over generic coordinate/place fallbacks.
    private static func visitQualityScore(_ visit: Visit) -> Double {
        var score = 0.0

        if !visit.placeID.isEmpty {
            score += 30
        }

        if let resolved = visit.resolved {
            score += resolved.confidence * 50

            if resolved.source.contains("google_places") {
                score += 20
            }

            if resolved.source.contains("google_geocode") {
                score += 12
            }

            if resolved.source.contains("fallback") {
                score -= 30
            }

            let title = resolved.title.lowercased()

            if title.contains("location ") {
                score -= 20
            }

            if title.contains("place ") {
                score -= 15
            }
        }

        let semantic = visit.semanticType.lowercased()

        if semantic != "unknown" && semantic != "aliased location" {
            score += 5
        }

        if visit.lat != nil && visit.lon != nil {
            score += 5
        }

        let durationMinutes = visit.end.timeIntervalSince(visit.start) / 60.0
        score += min(durationMinutes / 30.0, 5)

        return score
    }

    /// Merges nearby consecutive visits that represent one continuous stay.
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
                last.suppressedCandidates.append(contentsOf: visit.suppressedCandidates)
                last.suppressedCandidates = dedupeSuppressedCandidates(last.suppressedCandidates)

                if last.resolved == nil {
                    last.resolved = visit.resolved
                }

                if last.lat == nil {
                    last.lat = visit.lat
                }

                if last.lon == nil {
                    last.lon = visit.lon
                }

                merged.append(last)
            } else {
                merged.append(last)
                merged.append(visit)
            }
        }

        return merged
    }

    /// Converts one normalized visit into the exported/displayed event model.
    private static func makeEvent(from visit: Visit) -> ICSEvent {
        let resolved = visit.resolved
        let coordText = coordinateText(visit)
        let url = resolved?.url ?? mapsURL(visit)
        let duration = Int(round(visit.end.timeIntervalSince(visit.start) / 60.0))
        let title = title(for: visit)

        let suppressedText: String
        if visit.suppressedCandidates.isEmpty {
            suppressedText = ""
        } else {
            suppressedText = "\nSuppressed overlapping candidates:\n" + visit.suppressedCandidates.map {
                let distanceText: String
                if let distance = $0.distanceMetersFromPrimary {
                    distanceText = " · distance \(Int(distance.rounded()))m"
                } else {
                    distanceText = ""
                }

                return "- \($0.title)\(distanceText)"
            }.joined(separator: "\n")
        }

        let description = """
        Google Timeline
        Duration: \(duration) minutes
        Merged visits: \(visit.sourceCount)
        Original semantic type: \(visit.semanticType)
        Place ID: \(visit.placeID)
        Coordinate: \(coordText)
        Resolver source: \(resolved?.source ?? "none")
        Resolver confidence: \(String(format: "%.2f", resolved?.confidence ?? 0))
        Resolver debug: \(resolved?.debugMessage ?? "")
        \(url.isEmpty ? "" : "Google Maps: \(url)")\(suppressedText)
        """

        return ICSEvent(
            id: stableUID(visit: visit, title: title),
            summary: title,
            location: resolved?.subtitle.isEmpty == false ? resolved!.subtitle : coordText,
            description: description,
            url: url,
            start: visit.start,
            end: visit.end,
            lat: visit.lat,
            lon: visit.lon,
            suppressedCandidates: visit.suppressedCandidates
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        return isoFormatterWithFractionalSeconds.date(from: value)
            ?? isoFormatterNoFractionalSeconds.date(from: value)
    }

    /// Parses Timeline geo strings like geo:1.234,103.456.
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

    /// Chooses display title from resolved name, coordinate fallback, semantic, or generic fallback.
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

    /// Creates a Google Maps URL from place ID first, coordinates second.
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

    /// Stable event ID used by ICS export and incremental UI updates.
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

    /// Haversine distance used for conflict/merge distance checks.
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
