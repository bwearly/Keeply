//
//  KeeplyApp.swift
//  Keeply
//
//  Created by Blake Early on 1/5/26.
//

import SwiftUI
import CoreData

@main
struct KeeplyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
