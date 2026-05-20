//
//  TracesApp.swift
//  Traces
//
//  Created by Renchi Li on 20/5/26.
//

import SwiftUI
import CoreData

@main
struct TracesApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
