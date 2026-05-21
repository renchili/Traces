import Foundation

// MARK: - Google location resolver
// Resolves Google Timeline place IDs / coordinates into displayable names,
// addresses, map URLs, and merge keys. The resolver always uses cache first so
// repeated imports do not keep calling Google APIs for the same place.

final class GoogleLocationResolver {
    private let apiKey: String

    // Fast in-memory cache for one import run.
    private var memoryCache: [String: ResolvedLocation] = [:]

    // Persistent cache shared across app launches/imports.
    private let persistentCache = LocationCacheStore.shared

    init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves a batch of unique location requests.
    ///
    /// Returned dictionary is keyed by `LocationResolveRequest.cacheKey` so
    /// TimelineProcessor can attach results back to visits without relying on order.
    func resolveAll(_ requests: [LocationResolveRequest]) async -> [String: ResolvedLocation] {
        var result: [String: ResolvedLocation] = [:]
        let uniqueRequests = Array(Set(requests))

        for request in uniqueRequests {
            result[request.cacheKey] = await resolve(request)
        }

        return result
    }

    /// Resolves one request through memory cache, persistent cache, then network/fallback.
    private func resolve(_ request: LocationResolveRequest) async -> ResolvedLocation {
        if let cached = memoryCache[request.cacheKey] {
            return withCacheSource(cached, suffix: "memory_cache")
        }

        if let cached = await persistentCache.get(request.cacheKey) {
            memoryCache[request.cacheKey] = cached
            return withCacheSource(cached, suffix: "local_cache")
        }

        let resolved = await resolveUncached(
            placeID: request.placeID,
            lat: request.lat,
            lon: request.lon
        )

        memoryCache[request.cacheKey] = resolved

        // Only persist successful API-backed results. Fallbacks may be caused by
        // temporary network/API errors and should not poison the cache forever.
        if resolved.shouldPersistToCache {
            await persistentCache.set(resolved, for: request.cacheKey)
        }

        return resolved
    }

    /// Network resolution cascade. Place ID is preferred over reverse geocoding.
    private func resolveUncached(placeID: String, lat: Double?, lon: Double?) async -> ResolvedLocation {
        if apiKey.isEmpty {
            return fallback(
                placeID: placeID,
                lat: lat,
                lon: lon,
                reason: "No Google API key. Loaded fallback only."
            )
        }

        if !placeID.isEmpty {
            // Highest quality: Places API New by place resource ID.
            if let resolved = await resolveByPlaceIDNew(placeID, lat: lat, lon: lon) {
                return resolved
            }

            // Compatibility fallback for projects with legacy Places enabled.
            if let resolved = await resolveByPlaceIDLegacy(placeID, lat: lat, lon: lon) {
                return resolved
            }

            // Geocoding by place_id often works even when Places is unavailable.
            if let resolved = await geocodeByPlaceID(placeID, lat: lat, lon: lon) {
                return resolved
            }

            // Last API attempt: reverse geocode coordinates if present.
            if let lat, let lon, let resolved = await reverseGeocodeByLatLng(lat: lat, lon: lon, placeID: placeID) {
                return resolved
            }

            return fallback(
                placeID: placeID,
                lat: lat,
                lon: lon,
                reason: "All Google resolvers failed. Check DNS/network/API key/billing/API restrictions."
            )
        }

        if let lat, let lon {
            if let resolved = await reverseGeocodeByLatLng(lat: lat, lon: lon, placeID: placeID) {
                return resolved
            }

            return fallback(
                placeID: placeID,
                lat: lat,
                lon: lon,
                reason: "Reverse geocoding failed."
            )
        }

        return fallback(
            placeID: placeID,
            lat: lat,
            lon: lon,
            reason: "No placeID or coordinates available."
        )
    }

    /// Places API New lookup. Returns the best display name/address for a place ID.
    private func resolveByPlaceIDNew(_ placeID: String, lat: Double?, lon: Double?) async -> ResolvedLocation? {
        let encodedPlaceID = placeID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? placeID

        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(encodedPlaceID)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "id,displayName,formattedAddress,location,types",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return nil
            }

            if !(200..<300).contains(http.statusCode) {
                printAPIError(prefix: "Places API New", statusCode: http.statusCode, data: data)
                return nil
            }

            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let displayNameObject = object["displayName"] as? [String: Any]
            let displayName = displayNameObject?["text"] as? String
            let formattedAddress = object["formattedAddress"] as? String

            let title =
                Self.clean(displayName)
                ?? Self.clean(formattedAddress)
                ?? "Place \(placeID)"

            let subtitle =
                Self.clean(formattedAddress)
                ?? Self.coordText(lat: lat, lon: lon)

            return ResolvedLocation(
                title: title,
                subtitle: subtitle,
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: "placeID:\(placeID)",
                source: "google_places_new",
                confidence: 1.0,
                debugMessage: "Resolved by Places API New."
            )
        } catch {
            print("Places API New exception: \(error.localizedDescription)")
            return nil
        }
    }

    /// Legacy Places Details lookup.
    private func resolveByPlaceIDLegacy(_ placeID: String, lat: Double?, lon: Double?) async -> ResolvedLocation? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/place/details/json")
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: placeID),
            URLQueryItem(name: "fields", value: "name,formatted_address,geometry,type,place_id"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                return nil
            }

            if !(200..<300).contains(http.statusCode) {
                printAPIError(prefix: "Places API Legacy", statusCode: http.statusCode, data: data)
                return nil
            }

            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let status = object["status"] as? String, status != "OK" {
                print("Places API Legacy status: \(status)")
                if let message = object["error_message"] as? String {
                    print("Places API Legacy message: \(message)")
                }
                return nil
            }

            guard let result = object["result"] as? [String: Any] else {
                return nil
            }

            let name = result["name"] as? String
            let formattedAddress = result["formatted_address"] as? String

            let title =
                Self.clean(name)
                ?? Self.clean(formattedAddress)
                ?? "Place \(placeID)"

            let subtitle =
                Self.clean(formattedAddress)
                ?? Self.coordText(lat: lat, lon: lon)

            return ResolvedLocation(
                title: title,
                subtitle: subtitle,
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: "placeID:\(placeID)",
                source: "google_places_legacy",
                confidence: 0.98,
                debugMessage: "Resolved by Places API Legacy."
            )
        } catch {
            print("Places API Legacy exception: \(error.localizedDescription)")
            return nil
        }
    }

    /// Geocoding API lookup using place_id.
    private func geocodeByPlaceID(_ placeID: String, lat: Double?, lon: Double?) async -> ResolvedLocation? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "place_id", value: placeID),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                return nil
            }

            if !(200..<300).contains(http.statusCode) {
                printAPIError(prefix: "Geocoding by place_id", statusCode: http.statusCode, data: data)
                return nil
            }

            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let status = object["status"] as? String, status != "OK" {
                print("Geocoding by place_id status: \(status)")
                if let message = object["error_message"] as? String {
                    print("Geocoding by place_id message: \(message)")
                }
                return nil
            }

            guard
                let results = object["results"] as? [[String: Any]],
                let first = results.first
            else {
                return nil
            }

            let formattedAddress = first["formatted_address"] as? String

            let title =
                Self.clean(formattedAddress)
                ?? "Place \(placeID)"

            let subtitle =
                Self.clean(formattedAddress)
                ?? Self.coordText(lat: lat, lon: lon)

            return ResolvedLocation(
                title: title,
                subtitle: subtitle,
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: "placeID:\(placeID)",
                source: "google_geocode_place_id",
                confidence: 0.85,
                debugMessage: "Resolved by Geocoding API place_id."
            )
        } catch {
            print("Geocoding by place_id exception: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reverse geocoding fallback when coordinates are available.
    private func reverseGeocodeByLatLng(lat: Double, lon: Double, placeID: String) async -> ResolvedLocation? {
        var components = URLComponents(string: "https://maps.googleapis.com/maps/api/geocode/json")
        components?.queryItems = [
            URLQueryItem(name: "latlng", value: "\(lat),\(lon)"),
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                return nil
            }

            if !(200..<300).contains(http.statusCode) {
                printAPIError(prefix: "Reverse Geocoding latlng", statusCode: http.statusCode, data: data)
                return nil
            }

            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            if let status = object["status"] as? String, status != "OK" {
                print("Reverse Geocoding status: \(status)")
                if let message = object["error_message"] as? String {
                    print("Reverse Geocoding message: \(message)")
                }
                return nil
            }

            guard
                let results = object["results"] as? [[String: Any]],
                let first = results.first,
                let address = Self.clean(first["formatted_address"] as? String)
            else {
                return nil
            }

            let coord = Self.coordText(lat: lat, lon: lon)

            return ResolvedLocation(
                title: address,
                subtitle: coord,
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: placeID.isEmpty
                    ? "coord:\(LocationResolveRequest.roundedCoordKey(lat: lat, lon: lon))"
                    : "placeID:\(placeID)",
                source: "google_reverse_geocode_latlng",
                confidence: 0.75,
                debugMessage: "Resolved by Geocoding API latlng."
            )
        } catch {
            print("Reverse Geocoding exception: \(error.localizedDescription)")
            return nil
        }
    }

    /// Local fallback used when API resolution is unavailable or fails.
    private func fallback(placeID: String, lat: Double?, lon: Double?, reason: String) -> ResolvedLocation {
        let coord = Self.coordText(lat: lat, lon: lon)

        if let lat, let lon {
            return ResolvedLocation(
                title: coord.isEmpty ? "Timeline Location" : "Location \(coord)",
                subtitle: !placeID.isEmpty ? "\(coord) · Place ID: \(placeID)" : coord,
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: !placeID.isEmpty
                    ? "placeID:\(placeID)"
                    : "coord:\(LocationResolveRequest.roundedCoordKey(lat: lat, lon: lon))",
                source: !placeID.isEmpty ? "place_id_fallback" : "coordinate_fallback",
                confidence: 0.3,
                debugMessage: reason
            )
        }

        if !placeID.isEmpty {
            return ResolvedLocation(
                title: "Place \(placeID)",
                subtitle: "Place ID: \(placeID)",
                url: googleMapsURL(placeID: placeID, lat: lat, lon: lon),
                mergeKey: "placeID:\(placeID)",
                source: "place_id_fallback",
                confidence: 0.2,
                debugMessage: reason
            )
        }

        return ResolvedLocation(
            title: "Timeline Location",
            subtitle: "",
            url: "",
            mergeKey: UUID().uuidString,
            source: "empty_fallback",
            confidence: 0,
            debugMessage: reason
        )
    }

    /// Adds cache provenance to a cached resolved location for debugging.
    private func withCacheSource(_ cached: ResolvedLocation, suffix: String) -> ResolvedLocation {
        ResolvedLocation(
            title: cached.title,
            subtitle: cached.subtitle,
            url: cached.url,
            mergeKey: cached.mergeKey,
            source: "\(cached.source)_\(suffix)",
            confidence: cached.confidence,
            debugMessage: "Loaded from \(suffix.replacingOccurrences(of: "_", with: " "))."
        )
    }

    /// Builds a stable Google Maps URL from place ID or coordinates.
    private func googleMapsURL(placeID: String, lat: Double?, lon: Double?) -> String {
        if !placeID.isEmpty {
            return "https://www.google.com/maps/place/?q=place_id:\(placeID)"
        }

        if let lat, let lon {
            return "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)"
        }

        return ""
    }

    private func printAPIError(prefix: String, statusCode: Int, data: Data) {
        let body = String(data: data, encoding: .utf8) ?? ""
        print("\(prefix) error \(statusCode): \(body)")
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func coordText(lat: Double?, lon: Double?) -> String {
        guard let lat, let lon else { return "" }
        return String(format: "%.6f,%.6f", lat, lon)
    }
}
