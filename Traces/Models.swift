import Foundation

struct ICSEvent: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let summary: String
    let location: String
    let description: String
    let url: String
    let start: Date?
    let end: Date?

    static func == (lhs: ICSEvent, rhs: ICSEvent) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

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

struct TimelineOptions: Codable, Sendable {
    var lastDays: Int = 14
    var minStayMinutes: Double = 15
    var removeHomeOverMinutes: Double = 60
    var localMergeGapMinutes: Double = 30
    var localMergeDistanceMeters: Double = 250
}

struct ResolvedLocation: Hashable, Codable, Sendable {
    let title: String
    let subtitle: String
    let url: String
    let mergeKey: String
    let source: String
    let confidence: Double
    let debugMessage: String

    var shouldPersistToCache: Bool {
        source == "google_places_new"
        || source == "google_places_legacy"
        || source == "google_geocode_place_id"
        || source == "google_reverse_geocode_latlng"
    }
}

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

    static func cacheKey(placeID: String, lat: Double?, lon: Double?) -> String {
        if !placeID.isEmpty {
            return "placeID:\(placeID)"
        }

        if let lat, let lon {
            return "coord:\(roundedCoordKey(lat: lat, lon: lon))"
        }

        return "empty"
    }

    static func roundedCoordKey(lat: Double, lon: Double) -> String {
        String(format: "%.5f,%.5f", lat, lon)
    }
}
