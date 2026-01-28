import SwiftUI
import CoreLocation

// Custom themes for each location
struct locationThemeManager: Codable, Equatable {
    enum GradientStyle: String, CaseIterable, Identifiable, Codable {
        case soft, vivid // gradient styles
        var id: String { rawValue }
    }

    var color: ThemeColor = .blue
    var iconName: String = "mappin.and.ellipse"
    var gradient: GradientStyle = .soft
}

// Store different theme colours the user can pick from
enum ThemeColor: String, CaseIterable, Identifiable, Codable {
    case blue, green, orange, pink, purple, red, teal, yellow, gray

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .pink:   return .pink
        case .purple: return .purple
        case .red:    return .red
        case .teal:   return .teal
        case .yellow: return .yellow
        case .gray:   return .gray
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let key = "location_specifc_themes"

    // Any change to this will trigger SwiftUI to refresh dependents
    @Published private(set) var revision = UUID()
    
    // Store the themes so it saves in the application
    private var cache: [String: Data] {
        get { (UserDefaults.standard.dictionary(forKey: key) as? [String: Data]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    func theme(for location: String) -> locationThemeManager {
        let defaultThemes = location.lowercased()
        if let data = cache[defaultThemes],
           let t = try? JSONDecoder().decode(locationThemeManager.self, from: data) {
            return t
        }
        // Defaults per location
        switch defaultThemes {
        case "work":        return .init(color: .blue,   iconName: "briefcase.fill",  gradient: .soft)
        case "home":        return .init(color: .green,  iconName: "house.fill",      gradient: .soft)
        case "gym":         return .init(color: .orange, iconName: "dumbbell.fill",   gradient: .vivid)
        case "park":        return .init(color: .teal,   iconName: "leaf.fill",       gradient: .soft)
        case "supermarket": return .init(color: .pink,   iconName: "cart.fill",       gradient: .soft)
        default:            return .init()
        }
    }
    // Function to set the theme and reload the view
    func setTheme(_ theme: locationThemeManager, for location: String) {
        var mapTheme = cache
        mapTheme[location.lowercased()] = try? JSONEncoder().encode(theme)
        cache = mapTheme
        // Publish a change so SwiftUI re-renders with the new theme
        DispatchQueue.main.async { self.revision = UUID() }
    }
}

// Used to build the themeed backgrounds
// aided with https://developer.apple.com/documentation/swiftui/lineargradient
private func themedBackground(_ t: locationThemeManager) -> LinearGradient {
    let gradientTint = t.color.swiftUIColor
    switch t.gradient {
    case .soft:
        return LinearGradient(
            colors: [gradientTint.opacity(0.2), gradientTint.opacity(0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    case .vivid:
        return LinearGradient(
            colors: [gradientTint.opacity(0.4), gradientTint.opacity(0.15)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

struct FocusView: View {
    @Binding var reloadFocusView: UUID
    @State private var topLocationTask: TaskSample?
    @State private var locationTasks: [TaskSample] = []
    @AppStorage("selectedLocationMode") private var selectedLocationMode: String = "Automatic"

    @ObservedObject private var themeManager = ThemeManager.shared

    @State private var showThemeEditor = false
    @State private var editingTheme = locationThemeManager()

    private let headerHeight: CGFloat = 52

    var body: some View {
        let theme = themeManager.theme(for: selectedLocationMode)
        let accent = theme.color.swiftUIColor

        ScrollView {
            VStack {
                if let top = topLocationTask {
                    VStack(spacing: 6) {
                        Text(top.title)
                            .font(.headline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Text(top.dateTime, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(top.priority.capitalized)
                            .font(.caption2.weight(.bold))
                            .foregroundColor(priorityColours(for: top.priority))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(themedBackground(theme))
                    )
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(locationTasks) { task in
                        taskRow(task)
                    }

                    if locationTasks.isEmpty {
                        Text(selectedLocationMode == "Automatic"
                             ? "Select a Location Mode to see focused tasks."
                             : "No tasks found at this location yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HeaderBar(
                icon: theme.iconName,
                title: "\(selectedLocationMode) Tasks",
                tint: accent,
                showPaint: selectedLocationMode != "Automatic",
                onPaint: {
                    editingTheme = theme
                    showThemeEditor = true
                }
            )
            .frame(height: headerHeight)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .bottom)
        }
        .tint(accent)
        .onAppear { loadLocationFocusedTasks() }
        .onChange(of: reloadFocusView) { loadLocationFocusedTasks() }
        .sheet(isPresented: $showThemeEditor) {
            ThemeEditor(locationName: selectedLocationMode, theme: $editingTheme) { newTheme in
                ThemeManager.shared.setTheme(newTheme, for: selectedLocationMode)
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ task: TaskSample) -> some View {
        let t = themeManager.theme(for: task.location)

        VStack {
            Text(task.title)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text(task.dateTime, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(task.priority.capitalized)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .foregroundColor(priorityColours(for: task.priority))
            }
        }
        .padding(10) // ensures border actually surround tasks
        .background(RoundedRectangle(cornerRadius: 10).fill(themedBackground(t)))
    }

    // load tasks at specific locations and set the priority by calling model
    func loadLocationFocusedTasks() {
        let rawMode = selectedLocationMode
        guard rawMode != "Automatic" else {
            self.topLocationTask = nil
            self.locationTasks = []
            return
        }

        let tasks = TaskStorage.load()
        let filtered = tasks.filter { $0.location == rawMode }
        locationTasks = filtered

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

        self.topLocationTask = classifier?.topPriorityTask(from: filtered, contextProvider: { _ in
            PredictionContext(currentDate: Date(), currentLocationCategory: rawMode)
        })
    }
}

// Header bar created to allow the user to see the current location and work task
private struct HeaderBar: View {
    let icon: String
    let title: String
    let tint: Color
    let showPaint: Bool
    let onPaint: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if showPaint {
                Button(action: onPaint) {
                    Image(systemName: "paintbrush")
                        // needed to make the butto nbigger and easier to press.
                        .font(.headline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}

// Theme editor to change the theems for each task.
struct ThemeEditor: View {
    let locationName: String
    @Binding var theme: locationThemeManager
    var onSave: (locationThemeManager) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Color")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(ThemeColor.allCases) { token in
                                Circle()
                                    .fill(token.swiftUIColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle().stroke(
                                            Color.white.opacity(theme.color == token ? 1 : 0), lineWidth: 2
                                        )
                                    )
                                    .onTapGesture { theme.color = token }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(header: Text("Icon")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            let icons = ["briefcase.fill","house.fill","dumbbell.fill","cart.fill","leaf.fill","clock.fill","star.fill","mappin.and.ellipse"]
                            ForEach(icons, id:\.self) { name in
                                Image(systemName: name)
                                    .frame(width: 30, height: 30)
                                    .padding(6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(theme.iconName == name ? Color.gray.opacity(0.2) : .clear)
                                    )
                                    .onTapGesture { theme.iconName = name }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(header: Text("Style")) {
                    Picker("Gradient", selection: $theme.gradient) {
                        ForEach(locationThemeManager.GradientStyle.allCases) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                }
            }
            .navigationTitle("\(locationName) Theme")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(theme)
                        dismiss()
                    }
                }
            }
        }
    }
}

// Preview screen
#Preview {
    struct FocusViewPreviewWrapper: View {
        @State private var reloadFocusView = UUID()

        var body: some View {
            FocusView(reloadFocusView: $reloadFocusView)
                .onAppear {
                    // Force preview to a specific location
                    UserDefaults.standard.set("Work", forKey: "selectedLocationMode")

                    // Seed some sample tasks into storage
                    let now = Date()
                    let samples = [
                        TaskSample(taskType: "Work",
                                   dateTime: now.addingTimeInterval(3600),
                                   duration: 60,
                                   location: "Work",
                                   title: "Finish quarterly report",
                                   description: "Compile KPIs and finalize slides",
                                   priority: "High"),
                    ]

                    // Save samples into TaskStorage for preview
                    TaskStorage.save(tasks: samples)
                }
        }
    }
    return FocusViewPreviewWrapper()
}
