import Foundation

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

    nonisolated init(id: String, summary: String, location: String, description: String, url: String, start: Date?, end: Date?, lat: Double?, lon: Double?, suppressedCandidates: [SuppressedCandidate] = []) {
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

struct SuppressedCandidate: Hashable, Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let placeID: String
    let lat: Double?
    let lon: Double?
    let start: Date?
    let end: Date?
    let distanceMetersFromPrimary: Double?

    nonisolated init(id: String, title: String, placeID: String, lat: Double?, lon: Double?, start: Date?, end: Date?, distanceMetersFromPrimary: Double?) {
        self.id = id
        self.title = title
        self.placeID = placeID
        self.lat = lat
        self.lon = lon
        self.start = start
        self.end = end
        self.distanceMetersFromPrimary = distanceMetersFromPrimary
    }

    nonisolated static func make(title: String, placeID: String, lat: Double?, lon: Double?, start: Date?, end: Date?, distanceMetersFromPrimary: Double?) -> SuppressedCandidate {
        SuppressedCandidate(id: UUID().uuidString, title: title, placeID: placeID, lat: lat, lon: lon, start: start, end: end, distanceMetersFromPrimary: distanceMetersFromPrimary)
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
    var excludedPlaceRules: [String] = []
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
        LocationResolveRequest(cacheKey: cacheKey(placeID: placeID, lat: lat, lon: lon), placeID: placeID, lat: lat, lon: lon)
    }

    static func cacheKey(placeID: String, lat: Double?, lon: Double?) -> String {
        if !placeID.isEmpty { return "placeID:\(placeID)" }
        if let lat, let lon { return "coord:\(roundedCoordKey(lat: lat, lon: lon))" }
        return "empty"
    }

    static func roundedCoordKey(lat: Double, lon: Double) -> String {
        String(format: "%.5f,%.5f", lat, lon)
    }
}
