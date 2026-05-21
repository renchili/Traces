import Foundation

// MARK: - Shared app models
// This file contains value-only data structures shared by the parser, resolver,
// persistence, views, and ICS codec. Models should not perform file IO, network
// calls, or SwiftUI rendering.

/// Final calendar-like event used by the UI, session store, and ICS export.
///
/// `summary/location/url/start/end/lat/lon` describe the currently selected final
/// event. `suppressedCandidates` stores alternate overlapping places for review;
/// those candidates are not exported as separate ICS events.
struct ICSEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let summary: String
    let location: String
    let description: String
    let url: String
    let start: Date?
    let end: Date?
    let lat: Double?
    let lon: Double?
    let suppressedCandidates: [SuppressedCandidate]

    /// Explicit nonisolated initializer avoids Swift 6 actor-isolation warnings
    /// when model values are created from actors such as SessionStore.
    nonisolated init(
        id: String,
        summary: String,
        location: String,
        description: String,
        url: String,
        start: Date?,
        end: Date?,
        lat: Double?,
        lon: Double?,
        suppressedCandidates: [SuppressedCandidate] = []
    ) {
        self.id = id
        self.summary = summary
        self.location = location
        self.description = description
        self.url = url
        self.start = start
        self.end = end
        self.lat = lat
        self.lon = lon
        self.suppressedCandidates = suppressedCandidates
    }

    /// Equality includes all display/export fields so EventUpsertService can
    /// detect when an imported event updated meaningful content.
    static func == (lhs: ICSEvent, rhs: ICSEvent) -> Bool {
        lhs.id == rhs.id
            && lhs.summary == rhs.summary
            && lhs.location == rhs.location
            && lhs.description == rhs.description
            && lhs.url == rhs.url
            && lhs.start == rhs.start
            && lhs.end == rhs.end
            && lhs.lat == rhs.lat
            && lhs.lon == rhs.lon
            && lhs.suppressedCandidates == rhs.suppressedCandidates
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Alternate location candidate suppressed during impossible-overlap collapse.
///
/// A candidate can later be promoted by the user to become the final ICSEvent.
struct SuppressedCandidate: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let placeID: String
    let lat: Double?
    let lon: Double?
    let start: Date?
    let end: Date?
    let distanceMetersFromPrimary: Double?

    nonisolated init(
        id: String,
        title: String,
        placeID: String,
        lat: Double?,
        lon: Double?,
        start: Date?,
        end: Date?,
        distanceMetersFromPrimary: Double?
    ) {
        self.id = id
        self.title = title
        self.placeID = placeID
        self.lat = lat
        self.lon = lon
        self.start = start
        self.end = end
        self.distanceMetersFromPrimary = distanceMetersFromPrimary
    }

    /// Convenience factory for processor-generated candidates.
    nonisolated static func make(
        title: String,
        placeID: String,
        lat: Double?,
        lon: Double?,
        start: Date?,
        end: Date?,
        distanceMetersFromPrimary: Double?
    ) -> SuppressedCandidate {
        SuppressedCandidate(
            id: UUID().uuidString,
            title: title,
            placeID: placeID,
            lat: lat,
            lon: lon,
            start: start,
            end: end,
            distanceMetersFromPrimary: distanceMetersFromPrimary
        )
    }
}

// MARK: - Google Timeline JSON DTOs
// Minimal Decodable structures for the Timeline export shape currently used by
// the app. Extra JSON fields are intentionally ignored.

struct TimelineEntry: Decodable, Sendable {
    let startTime: String?
    let endTime: String?
    let visit: TimelineVisit?
}

struct TimelineVisit: Decodable, Sendable {
    let topCandidate: TimelineCandidate?
}

struct TimelineCandidate: Decodable, Sendable {
    let semanticType: String?
    let placeID: String?
    let placeLocation: String?
}

// MARK: - Import options

/// User-configurable Timeline processing options.
struct TimelineOptions: Codable, Sendable {
    var lastDays: Int = 14
    var minStayMinutes: Double = 15
    var removeHomeOverMinutes: Double = 60
    var localMergeGapMinutes: Double = 30
    var localMergeDistanceMeters: Double = 250
}

// MARK: - Location resolution models

/// Human-readable location data returned by GoogleLocationResolver.
struct ResolvedLocation: Hashable, Codable, Sendable {
    let title: String
    let subtitle: String
    let url: String
    let mergeKey: String
    let source: String
    let confidence: Double
    let debugMessage: String

    /// Only successful API-backed resolutions should be persisted. Fallbacks may
    /// represent temporary network/API failures and should not poison the cache.
    var shouldPersistToCache: Bool {
        source == "google_places_new"
        || source == "google_places_legacy"
        || source == "google_geocode_place_id"
        || source == "google_reverse_geocode_latlng"
    }
}

/// One resolver request for a place ID or coordinate.
struct LocationResolveRequest: Hashable, Sendable {
    let cacheKey: String
    let placeID: String
    let lat: Double?
    let lon: Double?

    static func make(placeID: String, lat: Double?, lon: Double?) -> LocationResolveRequest {
        LocationResolveRequest(
            cacheKey: cacheKey(placeID: placeID, lat: lat, lon: lon),
            placeID: placeID,
            lat: lat,
            lon: lon
        )
    }

    /// Cache identity prefers place ID; coordinates are fallback identity.
    static func cacheKey(placeID: String, lat: Double?, lon: Double?) -> String {
        if !placeID.isEmpty {
            return "placeID:\(placeID)"
        }

        if let lat, let lon {
            return "coord:\(roundedCoordKey(lat: lat, lon: lon))"
        }

        return "empty"
    }

    /// Coordinate cache key rounded to avoid tiny GPS jitter creating duplicates.
    static func roundedCoordKey(lat: Double, lon: Double) -> String {
        String(format: "%.5f,%.5f", lat, lon)
    }
}
