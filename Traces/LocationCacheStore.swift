import Foundation

actor LocationCacheStore {
    static let shared = LocationCacheStore()

    private let defaultsKey = "traces.locationResolver.cache.v2"
    private var cache: [String: ResolvedLocation]

    private init() {
        self.cache = Self.loadFromDefaults(defaultsKey: defaultsKey)
    }

    func get(_ key: String) -> ResolvedLocation? {
        cache[key]
    }

    func set(_ value: ResolvedLocation, for key: String) {
        cache[key] = value
        save()
    }

    func setMany(_ values: [String: ResolvedLocation]) {
        for (key, value) in values {
            cache[key] = value
        }
        save()
    }

    func clear() {
        cache.removeAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    func count() -> Int {
        cache.count
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(cache)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Location cache save failed: \(error.localizedDescription)")
        }
    }

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
