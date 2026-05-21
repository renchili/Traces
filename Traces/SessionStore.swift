import Foundation

struct TracesSession: Sendable {
    let events: [ICSEvent]
    let selectedEventID: String?
    let fileName: String
    let generatedICS: String
    let savedAt: Date
}

actor SessionStore {
    static let shared = SessionStore()

    private let defaultsKey = "traces.lastSession.v3"

    private init() {}

    func load() -> TracesSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            return Self.decodeSession(object)
        } catch {
            print("Session load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ session: TracesSession) {
        do {
            let object = Self.encodeSession(session)
            let data = try JSONSerialization.data(withJSONObject: object, options: [])
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Session save failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func encodeSession(_ session: TracesSession) -> [String: Any] {
        [
            "events": session.events.map { encodeEvent($0) },
            "selectedEventID": session.selectedEventID as Any,
            "fileName": session.fileName,
            "generatedICS": session.generatedICS,
            "savedAt": session.savedAt.timeIntervalSince1970
        ]
    }

    private static func decodeSession(_ object: [String: Any]) -> TracesSession? {
        guard
            let eventObjects = object["events"] as? [[String: Any]],
            let fileName = object["fileName"] as? String,
            let generatedICS = object["generatedICS"] as? String
        else {
            return nil
        }

        let selectedEventID = object["selectedEventID"] as? String
        let savedAtTimestamp = object["savedAt"] as? Double ?? Date().timeIntervalSince1970

        let events = eventObjects.compactMap { decodeEvent($0) }

        return TracesSession(
            events: events,
            selectedEventID: selectedEventID,
            fileName: fileName,
            generatedICS: generatedICS,
            savedAt: Date(timeIntervalSince1970: savedAtTimestamp)
        )
    }

    private static func encodeEvent(_ event: ICSEvent) -> [String: Any] {
        var object: [String: Any] = [
            "id": event.id,
            "summary": event.summary,
            "location": event.location,
            "description": event.description,
            "url": event.url,
            "suppressedCandidates": event.suppressedCandidates.map { encodeSuppressedCandidate($0) }
        ]

        if let start = event.start {
            object["start"] = start.timeIntervalSince1970
        }

        if let end = event.end {
            object["end"] = end.timeIntervalSince1970
        }

        if let lat = event.lat {
            object["lat"] = lat
        }

        if let lon = event.lon {
            object["lon"] = lon
        }

        return object
    }

    private static func decodeEvent(_ object: [String: Any]) -> ICSEvent? {
        guard
            let id = object["id"] as? String,
            let summary = object["summary"] as? String,
            let location = object["location"] as? String,
            let description = object["description"] as? String,
            let url = object["url"] as? String
        else {
            return nil
        }

        let start: Date?
        if let timestamp = object["start"] as? Double {
            start = Date(timeIntervalSince1970: timestamp)
        } else {
            start = nil
        }

        let end: Date?
        if let timestamp = object["end"] as? Double {
            end = Date(timeIntervalSince1970: timestamp)
        } else {
            end = nil
        }

        let suppressedObjects = object["suppressedCandidates"] as? [[String: Any]] ?? []
        let suppressedCandidates = suppressedObjects.compactMap { decodeSuppressedCandidate($0) }

        return ICSEvent(
            id: id,
            summary: summary,
            location: location,
            description: description,
            url: url,
            start: start,
            end: end,
            lat: object["lat"] as? Double,
            lon: object["lon"] as? Double,
            suppressedCandidates: suppressedCandidates
        )
    }

    private static func encodeSuppressedCandidate(_ candidate: SuppressedCandidate) -> [String: Any] {
        var object: [String: Any] = [
            "id": candidate.id,
            "title": candidate.title,
            "placeID": candidate.placeID
        ]

        if let lat = candidate.lat {
            object["lat"] = lat
        }

        if let lon = candidate.lon {
            object["lon"] = lon
        }

        if let start = candidate.start {
            object["start"] = start.timeIntervalSince1970
        }

        if let end = candidate.end {
            object["end"] = end.timeIntervalSince1970
        }

        if let distance = candidate.distanceMetersFromPrimary {
            object["distanceMetersFromPrimary"] = distance
        }

        return object
    }

    private static func decodeSuppressedCandidate(_ object: [String: Any]) -> SuppressedCandidate? {
        guard
            let id = object["id"] as? String,
            let title = object["title"] as? String,
            let placeID = object["placeID"] as? String
        else {
            return nil
        }

        let start: Date?
        if let timestamp = object["start"] as? Double {
            start = Date(timeIntervalSince1970: timestamp)
        } else {
            start = nil
        }

        let end: Date?
        if let timestamp = object["end"] as? Double {
            end = Date(timeIntervalSince1970: timestamp)
        } else {
            end = nil
        }

        return SuppressedCandidate(
            id: id,
            title: title,
            placeID: placeID,
            lat: object["lat"] as? Double,
            lon: object["lon"] as? Double,
            start: start,
            end: end,
            distanceMetersFromPrimary: object["distanceMetersFromPrimary"] as? Double
        )
    }
}
