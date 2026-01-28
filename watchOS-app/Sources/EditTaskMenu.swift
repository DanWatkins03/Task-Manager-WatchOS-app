import SwiftUI

// Practically the same as add task menu so not really commented

struct EditTaskMenu: View {
    @Environment(\.presentationMode) var dismiss
    @Binding var task: TaskSample
    var onSave: () -> Void

    @State private var taskType: String
    @State private var date: Date
    @State private var time: Date
    @State private var duration: Double
    @State private var location: String
    @State private var title: String
    @State private var description: String
    @State private var priority: String
    
    @State private var showingTaskTypeSheet = false
    @State private var showingLocationSheet = false

    let taskTypes = ["Work", "Health", "Home", "Leasure", "Other"]
    let locations = ["Home", "Work", "Gym", "Supermarket", "Park", "Other"]

    init(task: Binding<TaskSample>, onSave: @escaping () -> Void) {
        _task = task
        self.onSave = onSave
        
        // Initialize state with task values
        _taskType = State(initialValue: task.wrappedValue.taskType)
        _date = State(initialValue: task.wrappedValue.dateTime)
        _time = State(initialValue: task.wrappedValue.dateTime)
        _duration = State(initialValue: task.wrappedValue.duration)
        _location = State(initialValue: task.wrappedValue.location)
        _title = State(initialValue: task.wrappedValue.title)
        _description = State(initialValue: task.wrappedValue.description)
        _priority = State(initialValue: task.wrappedValue.priority)
    }

    var body: some View {
        ScrollView {
            VStack {
                TextField("Title", text: $title)
                TextField("Description", text: $description)

                VStack(alignment: .leading) {
                    Text("Task Type").font(.headline)
                    Button(action: {
                        showingTaskTypeSheet.toggle()
                    }) {
                        Text(taskType)
                            .foregroundColor(.blue)
                            .padding()
                    }
                    .actionSheet(isPresented: $showingTaskTypeSheet) {
                        ActionSheet(
                            title: Text("Select Task Type"),
                            buttons: taskTypes.map { type in
                                .default(Text(type)) {
                                    taskType = type
                                }
                            }
                        )
                    }
                }

                VStack(alignment: .leading) {
                    Text("Select Date").font(.headline)
                    DatePicker("Select Date", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                        .frame(height: 100)
                }

                VStack(alignment: .leading) {
                    Text("Select Time").font(.headline)
                    DatePicker("Select Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(WheelDatePickerStyle())
                        .padding()
                }

                VStack(alignment: .leading) {
                    Text("Duration").font(.headline)
                    Stepper(value: $duration, in: 0...10, step: 0.25) {
                        Text("Duration: \(duration, specifier: "%.1f") hrs")
                            .font(.subheadline)
                    }
                }

                VStack(alignment: .leading) {
                    Text("Location").font(.headline)
                    Button(action: {
                        showingLocationSheet.toggle()
                    }) {
                        Text(location)
                            .foregroundColor(.blue)
                            .padding()
                    }
                    .actionSheet(isPresented: $showingLocationSheet) {
                        ActionSheet(
                            title: Text("Select Location"),
                            buttons: locations.map { loc in
                                .default(Text(loc)) {
                                    location = loc
                                }
                            }
                        )
                    }
                }

                Button("Save Changes") {
                    // Re-combine date and time
                    let updatedDate = combineDateAndTime(date: date, time: time)

                    // Re-run AI model
                    runAI()
                    // Update the bound task
                    task.taskType = taskType
                    task.dateTime = updatedDate
                    task.duration = duration
                    task.location = location
                    task.title = title
                    task.description = description
                    task.priority = priority

                    onSave()
                    dismiss.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
                .disabled(title.isEmpty)
            }
            .padding()
        }
        .navigationTitle("Edit Task")
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

struct EditTaskMenu_Previews: PreviewProvider {
    static var previews: some View {
        // Sample task to edit
        @State var sampleTask = TaskSample(
            id: UUID(),
            taskType: "Work",
            dateTime: Date(),
            duration: 1.5,
            location: "Office",
            title: "Project Update",
            description: "Review progress on current sprint",
            priority: "Medium"
        )

        return NavigationView {
            EditTaskMenu(task: $sampleTask) {
                print("Save tapped in preview")
            }
        }
    }
}
