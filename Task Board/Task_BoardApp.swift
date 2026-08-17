//
//  Task_BoardApp.swift
//  Task Board
//
//  Created by Rashika Poonacha on 17/08/26.
//

import SwiftUI
import CoreData

@main
struct Task_BoardApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
