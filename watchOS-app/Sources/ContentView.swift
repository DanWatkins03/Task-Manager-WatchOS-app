import SwiftUI
import CoreLocation

// Set of location types included in the program
enum LocationSwitcher: String, CaseIterable, Identifiable {

    var id: String { rawValue } // Gives a unique ID for swift UI
    
    // Different locations included in the program, can be expanded easily
    case automatic   = "Automatic"
    case home        = "Home"
    case work        = "Work"
    case gym         = "Gym"
    case supermarket = "Supermarket"
    case park        = "Park"
    case clinic      = "Clinic"
    case other       = "Other"
    case custom      = "Custom"

    // Default icons set for each task
    var icon: String {
        switch self {
        case .automatic:   return "location.circle"
        case .home:        return "house"
        case .work:        return "briefcase"
        case .gym:         return "figure.run"
        case .supermarket: return "cart"
        case .park:        return "leaf"
        case .clinic:      return "cross.case"
        case .other:       return "ellipsis.circle"
        case .custom:      return "mappin.and.ellipse"
        }
    }
}

// Different work preferences selected later in the personalisation tab.
enum FavourType: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case none = "No Preference"
    case home = "Home"
    case work = "Work"
    case health = "Health"
    case leasure = "Leisure"

}

// This is the view thats loaded straight away used to manage and handle the different tabs and menus
struct ContentView: View {
    @State private var isNavigating = false
    @State private var selectedTab = 1
    // So all menus can load the selected storage
    // Allows for binding so when location or favoured changes so does the menus
    @AppStorage("selectedLocationMode") var selectedLocationMode: String = LocationSwitcher.automatic.rawValue
    @AppStorage("favouredTaskType") private var favouredTaskType: String = "No Preference"
    // Reload for the focus view when the location/favoured task changes.
    @State private var reloadFocusView = UUID()
    // for main view
    @State private var reloadMainView = UUID()
    


    var body: some View {
        NavigationStack {
            // The tab view allows us to swipe to differnet menus such as settings or focus view.
            TabView(selection: $selectedTab) {
                // Focus view found on the left tab for specific work tasks
                FocusView(
                    reloadFocusView: $reloadFocusView)
                .tag(0)
                // The main view of the program as the middle and first tab thats loaded
                MainMenuView(
                    isNavigating: $isNavigating,
                    selectedLocationMode: $selectedLocationMode,
                    favouredTaskType: $favouredTaskType,
                    reloadFocusView: $reloadFocusView,
                    reloadMainView: $reloadMainView
                )
                .tag(1)
                // Personalisation View
                PersonalisationView(reloadMainView: $reloadMainView)
                .tag(2)

            }
            .tabViewStyle(.page)
        }
    }
}

// MARK: - MainMenuView
struct MainMenuView: View {
    @State private var topTask: TaskSample? // Top task is the one thats displayed first to the user
    @State private var expandMainTask = false // Expand top task to show snooze/completed
    
    @State private var showSnoozePicker = false // Menu is not expanded by default
    @State private var selectedSnoozeMinutes = 10
    // The following bindings mean when the variable changes so does the UI
    // E.g. when you change location it reloads the UI for focus view to show tasks at that location
    @Binding var isNavigating: Bool
    
    @Binding var selectedLocationMode: String
    
    @Binding var favouredTaskType: String
    
    @Binding var reloadFocusView: UUID
    
    @Binding var reloadMainView: UUID
    
    var body: some View {
        VStack(spacing: 10) {
            //
            if let task = topTask {
                VStack() {
                    Button(action: {
                        // Once you press the button the main task is expanded
                        expandMainTask.toggle() // Shows the snooze / compelte options
                    }) {
                        VStack(spacing: 6) {
                            // Text seen it at top
                            Text("Top Priority Task")
                                .font(.footnote)
                                .foregroundColor(.gray)
                            Text(task.title)
                                // The actual task thats loaded and shown
                                .font(.system(size: 24, weight: .bold)) // Set to bold and big
                                .multilineTextAlignment(.center) // Centered
                                .foregroundColor(.white)
                                .lineLimit(2) // Otherwise it takes up whole screen
                                // Make sure it expands vertically not to far to the edges of screen
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .center)
                            
                            Text("Priority: \(task.priority)")
                                .font(.caption)
                                // outputs the correct colour for the priority
                                // e.g. red for high
                                .foregroundColor(priorityColours(for: task.priority))
                            // Returns the date due for the task
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(formattedTime(task.dateTime))
                            }
                            .font(.footnote)
                            .foregroundColor(.gray)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Once you press the top task, the button triggers this func
                    if expandMainTask {
                        HStack {
                            Button(action: {
                                completeTopTask() // Func deletes the top task
                                // Trigger the update main view and load the new top task
                                reloadMainView = UUID()
                                
                            }) {
                                Label("Completed", systemImage: "checkmark.circle")
                            }
                            .foregroundColor(.green)
                            
                            Button(action: {
                                // Opens a different menu to select the duration you wish to snooze by
                                showSnoozePicker = true
                            }) {
                                Label("Snooze", systemImage: "zzz")
                            }
                            .foregroundColor(.orange)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        // if the user presses the snooze button it shows the snooze picker menu
                        .sheet(isPresented: $showSnoozePicker) {
                            VStack {
                                Text("Snooze Task")
                                    .font(.headline)
                                // Allows you to select different durations to snooze by
                                Picker("Snooze Duration", selection: $selectedSnoozeMinutes) {
                                    Text("5 minutes").tag(5)
                                    Text("10 minutes").tag(10)
                                    Text("15 minutes").tag(15)
                                    Text("30 minutes").tag(30)
                                    Text("60 minutes").tag(60)
                                }
                                // Removes another text box for snooze to clean it up
                                .labelsHidden()
                                
                                .frame(height: 100)
                                // prevents overflow of the picker
                                .clipped()
                                // Confirming it sets the snooze to the selected level
                                Button("Confirm") {
                                    snoozeTask(by: selectedSnoozeMinutes)
                                    showSnoozePicker = false // Remove the menu automatically
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding()
                        }
                    }
                }
                // makes the menu more centered
                .padding(.top, 15)
                .padding(.horizontal)
            // In case no tasks are actually stored in storage it will display no tasks
            } else {
                Text("No top task found")
                    .foregroundColor(.gray)
                    .padding()
            }
            // The HStack includes the two buttons found at the bottom of the device.
            HStack {
                NavigationLink(destination: AddTaskMenu()) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2) // Larger icon
                        .foregroundColor(.green)
                }
                .buttonStyle(.borderedProminent)
                
                NavigationLink(
                    destination: ViewTaskMenu()
                        // Used to keep track when the user exits the main menu.
                        // Used for items such as updates, to update UI when they exit the menu.
                        .onAppear { isNavigating = true }
                        .onDisappear { isNavigating = false }
                ) {
                    Image(systemName: "doc.text.magnifyingglass") // Seemed the most fitting for view tasks
                        // Otherwise the logo is tiny
                        .font(.title2)
                        .foregroundColor(.white)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .background(Color.black)
        }
        .onAppear {
            // Load top task straight away.
            loadTopTask()
        }
        // If the user changes their location in settings it calculates the new top task.
        .onChange(of: selectedLocationMode) {
            loadTopTask()
            reloadFocusView = UUID()
        }
        // If the user changes their task priority in settings it reloads the focus view
        .onChange(of: favouredTaskType) {
            loadTopTask()
            reloadFocusView = UUID()
        }
        .onChange(of: reloadMainView) {
            loadTopTask()
        }
        
    }
    // Used to convert the Date into an easy to read string for the top task
    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short // for the time so 21:00
        formatter.dateStyle = .short // for the date so 25/09/2025
        return formatter.string(from: date) // reutnr it as a string
    }
    
    
    func snoozeTask(by minutes: Int) {
        guard var task = topTask else { return }
        
        // sets the new date by adding the minutes from the selected ones in the snooze picker
        let newDate = Calendar.current.date(byAdding: .minute, value: minutes, to: task.dateTime) ?? task.dateTime
        // Saves it to top task
        task.dateTime = newDate
        topTask = task
        // Loads and finds the top task and saves the new date
        var allTasks = TaskStorage.load()
        if let index = allTasks.firstIndex(where: { $0.id == task.id }) {
            allTasks[index] = task
            TaskStorage.save(tasks: allTasks)
        }
    }
    
    // Func to load the top task, uses the ai model to determine which task returns the highest score.
    func loadTopTask() {
        let simulatedContext = selectedLocationMode
        
        let tasks = TaskStorage.load()
        
        // stores the model in classifier
        let classifier: CoreMLPriorityPredictor? = {
            do {
                return try CoreMLPriorityPredictor()
            } catch {
                #if DEBUG
                print("Failed to load CoreMLPriorityPredictor:", error)
                #endif
                return nil
            }
        }()

        // Uses the top priority task func in the neural network class to return the top task
        if let top = classifier?.topPriorityTask(from: tasks, contextProvider: { task in
            PredictionContext(currentDate: Date(), currentLocationCategory: simulatedContext)
        }) {
            self.topTask = top
        }
    }
    
    // marks the top task as completed, for this case just deletes the task as its done.
    func completeTopTask() {
        guard let task = topTask else { return }
        var allTasks = TaskStorage.load()
        TaskStorage.delete(task, from: &allTasks)  // Uses the delete function created in task class
        topTask = nil
    }
}

#Preview {
    ContentView()
}
    

