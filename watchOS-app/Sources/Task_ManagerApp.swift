//
//  Task_ManagerApp.swift
//  Task Manager Watch App
//
//  Created by Dannie Watkins on 19/03/2025.
//

import SwiftUI
// Loads the main view as Content view which is the home screen of this application
@main
struct Task_Manager_Watch_AppApp: App {
    @State private var isNavigating = false
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Class to deal with task storage in the application allowing for saving and loading of tasks.

class TaskStorage {
    static let fileName = "tasks.json" // This is the file name where the tasks will be stored and save as

    static var fileLocation: URL {
        // Locates the document directory
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // sets the path to the document directory + the file name
        return documents.appendingPathComponent(fileName)
    }
    // Save function used to save tasks
    static func save(tasks: [TaskSample]) {
        do { // Do and catch to ensure errors dont crash the code
            let taskData = try JSONEncoder().encode(tasks) // Covert task data into as JSON data
            try taskData.write(to: fileLocation, options: [.atomicWrite]) // writes the data to the file, atomic write ensures this is safe
        } catch {
            print("Saving tasks has run into an error \(error)")
        }
    }

    static func load() -> [TaskSample] {
        do { // Do and catch to ensure errors dont crash the code
            let taskData = try Data(contentsOf: fileLocation)
            return try JSONDecoder().decode([TaskSample].self, from: taskData)
        } catch {
            print("Failed to load any tasks.")
            return []
        }
    }
    
    static func delete(_ task: TaskSample, from tasks: inout [TaskSample]) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: index) // removes the task with the unique id
            save(tasks: tasks) // saves the updated list of tasks to disk
        }
    }
    
}
