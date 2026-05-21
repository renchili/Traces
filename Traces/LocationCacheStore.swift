import Foundation

// MARK: - Persistent location cache
// Stores successful place/coordinate resolution results across app launches.
// GoogleLocationResolver uses this actor before making network calls so repeated
// imports of the same place IDs are faster and cheaper.

actor LocationCacheStore {
    static let shared = LocationCacheStore()

    // Versioned key allows future cache schema changes without trying to decode
    // incompatible old data.
    private let defaultsKey = "traces.locationResolver.cache.v2"

    // Keyed by LocationResolveRequest.cacheKey, for example:
    // - placeID:<google-place-id>
    // - coord:<rounded-lat>,<rounded-lon>
    private var cache: [String: ResolvedLocation]

    private init() {
        self.cache = Self.loadFromDefaults(defaultsKey: defaultsKey)
    }

    /// Returns a cached resolved location for the request key.
    func get(_ key: String) -> ResolvedLocation? {
        cache[key]
    }

    /// Stores one resolved location and immediately persists the cache.
    func set(_ value: ResolvedLocation, for key: String) {
        cache[key] = value
        save()
    }

    /// Stores multiple resolved locations in one write.
    func setMany(_ values: [String: ResolvedLocation]) {
        for (key, value) in values {
            cache[key] = value
        }
        save()
    }

    /// Clears only location resolution cache. It does not clear imported events
    /// or the last working session.
    func clear() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// Number of cached places shown in the settings popover.
    func count() -> Int {
        cache.count
    }

    /// Persists the full cache dictionary as JSON in UserDefaults.
    private func save() {
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Location cache save failed: \(error.localizedDescription)")
        }
    }

    /// Loads cache on actor initialization. Corrupt or old data is ignored.
    private static func loadFromDefaults(defaultsKey: String) -> [String: ResolvedLocation] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode([String: ResolvedLocation].self, from: data)
        } catch {
            print("Location cache load failed: \(error.localizedDescription)")
            return [:]
        }
    }
}
