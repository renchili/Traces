//
//  SessionStore.swift
//  Traces
//
//  Created by Renchi Li on 20/5/26.
//

import Foundation

struct TracesSession: Codable, Sendable {
    let events: [ICSEvent]
    let selectedEventID: String?
    let fileName: String
    let generatedICS: String
    let savedAt: Date
}

actor SessionStore {
    static let shared = SessionStore()

    private let defaultsKey = "traces.lastSession.v1"

    private init() {}

    func load() -> TracesSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(TracesSession.self, from: data)
        } catch {
            print("Session load failed: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ session: TracesSession) {
        do {
            let data = try JSONEncoder().encode(session)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            print("Session save failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
