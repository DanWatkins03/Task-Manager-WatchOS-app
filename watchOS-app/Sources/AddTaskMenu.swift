import SwiftUI


// Needed to create a custom info button as the provided one is only available in iOS not watchOS.

struct aiVoiceHint: View {
    let text: String
    @State private var showAlert = false

    var body: some View {
        Image(systemName: "info.circle")
            .help(Text(text))
            .onTapGesture {
                // Shows alert on tap gesture
                showAlert = true
            }
            // Shows the alert menu, pressing okay exits the view
            .alert("Hint", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                // message is passed when called
                Text(text)
            }
    }
}

struct AddTaskMenu: View {
    @Environment(\.presentationMode) var presentationMode

    // All the different variables used when adding a task, to match the one the model processes
    @State private var taskType = "Work"
    @State private var date = Date()
    @State private var time = Date()
    @State private var duration = 0.0
    @State private var location = "Home"
    @State private var title = ""
    @State private var description = ""
    @State private var priority = ""

    @State private var showingTaskTypeSheet = false
    @State private var showingLocationSheet = false

    // Same for the different task types and locations
    let taskTypes = ["Work", "Health", "Home", "Leisure", "Other"]
    let locations = ["Home", "Work", "Gym", "Supermarket", "Park", "Other"]


    let recognizer = VoiceRecognizer(
        locations: ["Home", "Work", "Gym", "Supermarket", "Park", "Other"]
    )
    
    // Sets the voice recognizer class as a local variable
    @StateObject private var voiceManager = VoiceInputManager()

    var body: some View {
        ScrollView {
            Button {
                // Requests the voice input when selected
                voiceManager.requestDictation()
            } label: {
                HStack {
                    Text("AI & Voice Input")
                    Spacer(minLength: 8)
                    aiVoiceHint(text:
                        // Feed the text into the hint view
                        "Type your task as a sentence and the app fills in details automatically, " +
                        "or tap to speak and it will copy everything for you."
                    )
                }
            }

            VStack(spacing: 10) {
                // Text fields allow the user to enter with their keyboard
                TextField("Title", text: $title)
                TextField("Description", text: $description)

                // Task Type selector, shows the sheet to select different task types.
                VStack(alignment: .leading) {
                    Text("Task Type").font(.headline)
                    Button(action: { showingTaskTypeSheet.toggle() }) {
                        Text(taskType)
                            .foregroundColor(.blue)

                    } // The action sheet for selecting tasks
                    .actionSheet(isPresented: $showingTaskTypeSheet) {
                        ActionSheet(
                            title: Text("Select Task Type"),
                            // The different options are the different task types
                            buttons: taskTypes.map { type in
                                .default(Text(type)) { taskType = type }
                            }
                        )
                    }
                }

                // Date Picker integrated into swiftUI by default
                VStack(alignment: .leading) {
                    Text("Select Date").font(.headline)
                    // only for date not time as well
                    DatePicker("Select Date", selection: $date, displayedComponents: .date)
                        // Hide the title not needed
                        .labelsHidden()
                        // Rotate through the dates
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                        // Makes sure it doesnt take up a lot of the screen
                        .frame(height: 100)
                }

                // Same but utilises the picker for time
                VStack(alignment: .leading) {
                    Text("Select Time").font(.headline)
                    DatePicker("Select Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                }

                // Duration (hours)
                VStack(alignment: .leading) {
                    Text("Duration").font(.headline)
                    // Adjust by 15 minutes per click with step 0.25 up to 10 hrs
                    Stepper(value: $duration, in: 0...10, step: 0.25) {
                        Text("Duration: \(duration, specifier: "%.1f") hrs")
                            // Set font size so it doesnt take entire screen
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }

                // Same as task type but for location
                VStack(alignment: .leading) {
                    Text("Location").font(.headline)
                    Button(action: { showingLocationSheet.toggle() }) {
                        Text(location)
                            .foregroundColor(.blue)
                    }
                    .actionSheet(isPresented: $showingLocationSheet) {
                        ActionSheet(
                            title: Text("Select Location"),
                            buttons: locations.map { loc in
                                .default(Text(loc)) { location = loc }
                            }
                        )
                    }
                }

                // Saves task by copying the variables into storage of a default task
                Button("Save Task") {
                    let combinedDateTime = combineDateAndTime(date: date, time: time)
                    // Runs the AI to retrieve the task priority.
                    runAI()

                    var currentTasks = TaskStorage.load()
                    let newTask = TaskSample(
                        taskType: taskType,
                        dateTime: combinedDateTime,
                        duration: duration,
                        location: location,
                        title: title,
                        description: description,
                        priority: priority
                    )

                    currentTasks.append(newTask) // Add the new task to current tasks
                    TaskStorage.save(tasks: currentTasks) // Save the current task into storage
                    presentationMode.wrappedValue.dismiss() // Dismiss the view
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .padding()
        }
        .navigationTitle("Create New Task")
        // Listens for changes in the voice manager result so when the user adds a voice input
        // Parses the text and fills the boxes the user speaks about
        .onReceive(voiceManager.$result) { text in
            guard !text.isEmpty else { return }
            parseDictatedText(text)
        }
    }

    func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        var dateSelected = calendar.dateComponents([.year, .month, .day], from: date)
        let timeSelected = calendar.dateComponents([.hour, .minute], from: time)

        dateSelected.hour = timeSelected.hour
        dateSelected.minute = timeSelected.minute
        dateSelected.second = 0
        
        return calendar.date(from: dateSelected) ?? date
    }

    func parseDictatedText(_ input: String) {
        let result = recognizer.parse(text: input)
        title    = result.title
        duration = result.duration
        location = result.location
        taskType = result.taskType.rawValue

        if let parsedDate = result.date {
            date = parsedDate
            time = parsedDate
        }

    }
    // used to retrieve prediction label
    func runAI() {
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

        let newTask = TaskSample(
            taskType: taskType,
            dateTime: combineDateAndTime(date: date, time: time),
            duration: duration,
            location: location,
            title: title,
            description: description,
            priority: ""
        )

        let context = PredictionContext(currentDate: Date(), currentLocationCategory: location)
        if let prediction = classifier?.predictWithScore(task: newTask, contextProvider: { context }) {
            priority = prediction.label
            print("Predicted priority: \(prediction.label) (Confidence: \(String(format: "%.2f", prediction.score)))")
        } else {
            print("No prediction could be made.")
        }
    }
}

// Handles the text to speech on the apple watch uses the built in dictaton controller
class VoiceInputManager: NSObject, ObservableObject {
    @Published var result: String = ""

    func requestDictation() {
        // Presents the visible interface needed to for dictation
        WKExtension.shared().visibleInterfaceController?.presentTextInputController(
            withSuggestions: nil, // Does not show any suggestions
            allowedInputMode: .plain // only takes in text no emojis prevents errors
        ) { [weak self] dictatedString in
            // After the user finishes or cancels dictation
            guard let dictatedString = dictatedString as? [String], let first = dictatedString.first else {
                print(" No dictation result")
                return
            }
            print(" Dictated: \(first)")
            // Updates the result for swift to react to
            DispatchQueue.main.async {
                self?.result = first
            }
        }
    }
}

// simple preview
struct AddTaskMenu_Previews: PreviewProvider {
    static var previews: some View {
        AddTaskMenu()
    }
}
