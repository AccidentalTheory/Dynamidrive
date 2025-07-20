//
//  DynamidriveApp.swift
//  Dynamidrive
//
//  Created by Kai del Castillo on 3/1/25.
//

import SwiftUI
import SwiftData
import UIKit // Add this for AppDelegate

@main
struct DynamidriveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate // Add AppDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(sharedModelContainer)
                .environmentObject(appDelegate.audioController) // Add audioController as environment object
                .environmentObject(appDelegate.audioController.locationHandler) // Inject the shared LocationHandler
                .preferredColorScheme(.dark) // Force dark mode
        }
    }
}
