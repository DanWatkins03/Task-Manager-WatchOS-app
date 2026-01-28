import SwiftUI

// Wrapper to allow editing by identifying both index and task
struct TaskWrapper: Identifiable {
    var id: UUID { task.id }
    var task: TaskSample
    var index: Int
}

struct ViewTaskMenu: View {
    @State private var tasks: [TaskSample] = []
    @State private var selectedTaskWrapper: TaskWrapper? = nil
    @State private var sortBy: SortOption = .dateAscending
    
    enum SortOption: CaseIterable, Identifiable {
        case dateAscending
        case dateDescending
        case priorityAscending
        case priorityDescending

        var id: Self { self }

        var iconName: String {
            switch self {
            case .dateAscending:
                return "calendar.badge.plus" // Date going up
            case .dateDescending:
                return "calendar.badge.minus" // Date going down
            case .priorityAscending:
                return "flag" // Low to high priority
            case .priorityDescending:
                return "flag.fill" // High to low priority
            }
        }
    }
    
    init(tasks: [TaskSample] = []) {
        _tasks = State(initialValue: tasks)
    }
    
    // How the tasks are filtered by, so date or priority
    var sortedTasks: [TaskSample] {
        switch sortBy {
        case .dateAscending:
            return tasks.sorted(by: { $0.dateTime < $1.dateTime })
        case .dateDescending:
            return tasks.sorted(by: { $0.dateTime > $1.dateTime })
        case .priorityAscending:
            return tasks.sorted(by: { $0.priority < $1.priority })
        case .priorityDescending:
            return tasks.sorted(by: { $0.priority > $1.priority })
        }
    }
    
    @State private var searchText: String = ""
    // Filter tasks by searching for its title or description
    var filteredTasks: [TaskSample] {
        sortedTasks.filter { task in
            searchText.isEmpty ||
            task.title.localizedCaseInsensitiveContains(searchText) ||
            task.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 6) {
                TextField("Search", text: $searchText)
                // To select the filter option
                Picker("Sort", selection: $sortBy) {
                    ForEach(SortOption.allCases) { option in
                        Image(systemName: option.iconName)
                            .tag(option)
                    }
            }
            .pickerStyle(.automatic)
            .frame(width: 60)
            .offset(y:-10)
        }
        .padding(.horizontal)
            
            List {
                // Shows filtered tasks if searched for otherwise all tasks
                ForEach(filteredTasks, id: \.id) { task in
                    // Shows each task as as seperate box
                    VStack(alignment: .leading) {
                        Text(task.title).font(.headline)
                        Text(task.description).font(.caption).foregroundColor(.gray)
                        Text("Time: \(formattedDateTime(task.dateTime)) | Priority: \(task.priority)")
                            .font(.footnote).foregroundColor(.blue)
                    }
                    // you can swipe to either delete or edit the task
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTask(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            if let originalIndex = tasks.firstIndex(where: { $0.id == task.id }) {
                                selectedTaskWrapper = TaskWrapper(task: task, index: originalIndex)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Saved Tasks")
        .onAppear {
            if tasks.isEmpty {
                tasks = TaskStorage.load()
            }
        }
        // save tasks when the menu disappears
        .sheet(item: $selectedTaskWrapper) { wrapper in
            EditTaskMenu(task: $tasks[wrapper.index]) {
                TaskStorage.save(tasks: tasks)
            }
        }
    }
    
    func deleteTask(_ task: TaskSample) {
           TaskStorage.delete(task, from: &tasks)
       }
    
    func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy h:mm"
        return formatter.string(from: date)
    }
}
    // preview with random task
    struct ViewTaskMenu_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                ViewTaskMenu(tasks: [
                    TaskSample(
                        id: UUID(),
                        taskType: "Work",
                        dateTime: Date(),
                        duration: 2.0,
                        location: "Office",
                        title: "Team Meeting",
                        description: "Weekly team meeting to discuss progress.",
                        priority: "High"
                    )
                ])
            }
        }
    }

