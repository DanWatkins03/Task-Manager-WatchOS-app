import Foundation
import CoreLocation
import CoreML
import SwiftUI

// A list of priority colours the UI's can use later in the code, placed here instead of repeating in code.

func priorityColours(for priority: String) -> Color {
    switch priority.lowercased() {
    // Returns a different colour for each priority
    case "low": return .green
    case "medium": return .yellow
    case "high": return .red
    default: return .gray
    }
}

// Below represents the values each task will hold.

struct TaskSample: Identifiable, Codable {
    // This includes its unique ID, task title, location etc.
    var id = UUID()
    var taskType: String
    var dateTime = Date()
    var duration: Double
    var location: String
    var title: String
    var description: String
    var priority: String
}

// Context info for the model
// Returns the context data used when calculating how to show tasks such as their current location.
struct PredictionContext {
    var currentDate: Date
    var currentLocationCategory: String // "Work", "Home", etc.
}

// For the automatic mode, certain co ordinates represent certain locations
// just used this website for them https://www.randomcoords.com/region/england
let knownLocations: [String: CLLocationCoordinate2D] = [
    // Below are a random list of co ordinates for different locations.
    "Work": CLLocationCoordinate2D(latitude: 53.4378, longitude: 2.9552),
    "Home": CLLocationCoordinate2D(latitude: 51.5498, longitude: -0.3646),
    "Gym": CLLocationCoordinate2D(latitude: 51.5033, longitude: -0.1195),
    "Supermarket": CLLocationCoordinate2D(latitude: 50.7248, longitude: -1.8573),
    "Park": CLLocationCoordinate2D(latitude: 50.8322, longitude: -4.5301)
]

// This gives a 200m freedom for each location as they wont be in the exact co ordinate for each location
func currentLocationCategory(from userLocation: CLLocationCoordinate2D) -> String {
  
    let thresholdDistance = 200.0 // meters

    for (name, location) in knownLocations {
        let userLoc = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let knownLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
        if userLoc.distance(from: knownLoc) < thresholdDistance {
            return name
        }
    }
    return "Other"
}

// Below are a list of encodings the model is mapped to, reperesenting items such as location, urgent words etc.
let taskTypeEncoding = ["Work": 0, "Health": 1, "Home": 2, "Leisure": 3, "Other": 4]
let locationEncoding = ["Work": 0, "Home": 1, "Gym": 2, "Supermarket": 3, "Park": 4, "Clinic": 5, "Other": 6]
let urgentWordEncoding: [String] = ["urgent", "asap", "deadline", "important", "critical",
                                     "boss", "meeting", "presentation", "review"]
    


// Ensure that certain values always stay in range to prevent possible errors
private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    return min(hi, max(lo, v))
}

// One hot encoding was found using this documentation
// https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.OneHotEncoder.html
//  allows us to store each task and location independently in a vector so the nn can differentiate
private func oneHot(index: Int?, size: Int) -> [Double] {
    var v = Array(repeating: 0.0, count: size)
    if let i = index, i >= 0, i < size { v[i] = 1.0 }
    return v
}


// Build the 23-dim feature vector (must match CoreML training)
// This is esentially the one found in python so comments may be missing and found there
func encodeFeatures(sample: TaskSample, context: PredictionContext) -> [Double] {
    // --- time features from sample.dateTime ---
    let dt = sample.dateTime
    let cal = Calendar.current
    let hour = Double(cal.component(.hour, from: dt))

    // Map iOS weekday so  they are far apart instead of mon and sun appearing close they would be mon = 1 sun = 7
    let iosWeekday = cal.component(.weekday, from: dt)
    let dowPython = (iosWeekday + 5) % 7
    // For hours and days of week to make sure the model seems them for what they truly are
    // As 00:00 and 23:00 usually seem far apart but in reality they are close
    // This represents them in a way that they appear close together
    let hourSin = sin(2.0 * .pi * hour / 24.0)
    let hourCos = cos(2.0 * .pi * hour / 24.0)
    let dowSin  = sin(2.0 * .pi * Double(dowPython) / 7.0)
    let dowCos  = cos(2.0 * .pi * Double(dowPython) / 7.0)

    // Calculates and clamps the hours to make sure it doesnt go below 0
    let hoursUntilRaw = dt.timeIntervalSince(context.currentDate) / 3600.0
    let hoursUntil = max(0.0, hoursUntilRaw)
    // Caps the hour limit to 336 hours (2 weeks) so tasks exceeding that are treated as equally far away
    let clampedHours = clamp(hoursUntil, 0.0, 336.0) // 336 hours = 14 days
    let urgencyDecay = 1.0 - (clampedHours / 336.0) // Noramlised score

    // duration stored in minutes currently to match the dataset
    let durationHours = Double(sample.duration) * 60

    // Text extraction to get the title, and description and combine it into lowercase text
    let title = sample.title
    let desc  = sample.description
    let text  = (title + " " + desc).lowercased()
    //   Words in the title are weighted 50% stronger in the total word count
    let wordCount = 1.5 * Double(title.split(whereSeparator: { $0.isWhitespace }).count)
                  + Double(desc.split(whereSeparator: { $0.isWhitespace }).count)
    let charCount = Double(text.count)

    // Pads text with spaces so we can check each word
    let padded = " " + text + " "
    // checks the amount of times urgent words appear in the text
    let urgentCount = urgentWordEncoding.reduce(0.0) { acc, w in
        acc + (padded.contains(" \(w) ") ? 1.0 : 0.0)
    }

    // One hot encoding features for each location and task type
    let ttIdx = taskTypeEncoding[sample.taskType] ?? taskTypeEncoding["Other"]!
    let locIdx = locationEncoding[sample.location] ?? locationEncoding["Other"]!

    let ttOH  = oneHot(index: ttIdx, size: taskTypeEncoding.count)   // 5
    let locOH = oneHot(index: locIdx, size: locationEncoding.count)  // 7

    // context match flag so if the location matches the context location set to 1 otherwise 0
    let ctxMatch = (sample.location == context.currentLocationCategory) ? 1.0 : 0.0

    // Features must be in the order they are in python or they will mismatch which would severely harm results
    var features: [Double] = [
        clampedHours,        // 1
        durationHours,       // 2
        wordCount,           // 3
        charCount,           // 4
        urgentCount,         // 5
        urgencyDecay,        // 6
        hourSin, hourCos,    // 7,8
        dowSin,  dowCos,     // 9,10
        ctxMatch             // 11
    ]
    // one hot encoding features
    features.append(contentsOf: ttOH)    // 12..16
    features.append(contentsOf: locOH)   // 17..23

    return features
    
}

// This is the actual model, it loads the CoreML modded created in Python under NEURAL.PY
// Created as class to run functions such as predict with score
class CoreMLPriorityPredictor {
    private let model: PriorityNN

    // Load default model, the program will crash if the model is not available.
    enum ModelLoadError: Error {
            case failedToLoadModel(Error)
        }

        init() throws {
            let config = MLModelConfiguration()
            do {
                self.model = try PriorityNN(configuration: config)
            } catch {
                throw ModelLoadError.failedToLoadModel(error)
            }
        }
    
      func recomputeAndPersistAll(contextLocation: String) -> [TaskSample] {
          var tasks = TaskStorage.load()
          let priorityOrder: [String] = ["Low", "Medium", "High"]
          let labels = ["High", "Low", "Medium"]
          let favoured = UserDefaults.standard.string(forKey: "favouredTaskType") ?? "No Preference"
          let boostFactor: Double = 1.2

          for i in tasks.indices {
              let task = tasks[i]
              // encode features as you already do
              let features = encodeFeatures(sample: task,
                                            context: PredictionContext(currentDate: Date(),
                                                                       currentLocationCategory: contextLocation))

              guard let mlArray = try? MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .double) else { continue }
              for (j, v) in features.enumerated() { mlArray[j] = NSNumber(value: v) }

              guard let pred = try? model.prediction(input: PriorityNNInput(input: mlArray)) else { continue }

              // base scores
              var scores = (0..<pred.prob_output.count).map { pred.prob_output[$0].doubleValue }

              // boost if matches user preference
              if favoured != "No Preference", task.taskType == favoured {
                  scores = scores.map { $0 * boostFactor }
              }

              // choose top + promotion rule
              let topIdx = scores.enumerated().max(by: { $0.element < $1.element })!.offset
              var finalLabel = labels[topIdx]
              let finalScore = scores[topIdx]
              if finalScore > 1.0, let cur = priorityOrder.firstIndex(of: finalLabel), cur < priorityOrder.count - 1 {
                  finalLabel = priorityOrder[cur + 1]
              }

              // persist only if changed
              if tasks[i].priority != finalLabel {
                  tasks[i].priority = finalLabel
              }
          }

          TaskStorage.save(tasks: tasks)
          return tasks
      }

    // Runs the model returnign the label and its score which is the probability it belongs to that class
    func predictWithScore(task: TaskSample, contextProvider: () -> PredictionContext) -> (label: String, score: Double)? {
        let context = contextProvider() // Supply current context such as location and time
        let features = encodeFeatures(sample: task, context: context)
        // The task type the user has set as their preference, boosting the score
        let favoured = UserDefaults.standard.string(forKey: "favouredTaskType") ?? "No Preference"
        // Default 20%, with more time would implement a setting the user can choose from
        let boostFactor: Double = 1.2
        // Priority labels
        let labels = ["High", "Low", "Medium"]
        let priorityOrder: [String] = ["Low", "Medium", "High"]

        guard let mlMultiArray = try? MLMultiArray(shape: [NSNumber(value: features.count)], dataType: .double) else {
            print("Failed to create MLMultiArray")
            return nil
        }

        for (i, value) in features.enumerated() {
            mlMultiArray[i] = NSNumber(value: value)
        }

        // Run the model
        let input = PriorityNNInput(input: mlMultiArray)

        do {
            let prediction = try model.prediction(input: input)

            // Read the class probabilites from vector output
            // prob_output is the name chosen from coreml export in python
            let originalScores = (0..<prediction.prob_output.count).map { prediction.prob_output[$0].doubleValue }

            // Print the orgianl scores before boosting
            print("Original Scores for '\(task.title)':")
            for (i, val) in originalScores.enumerated() {
                print("   - \(labels[i]): \(String(format: "%.2f", val))")
            }

            var boostedScores = originalScores

            // Apply boost if task type matches
            if favoured != "No Preference", task.taskType == favoured {
                print("Boosting scores for favoured task type '\(favoured)'")
                for i in 0..<boostedScores.count {
                    boostedScores[i] *= boostFactor
                }

                print(" Boosted Scores:")
                for (i, val) in boostedScores.enumerated() {
                    print("     - \(labels[i]): \(String(format: "%.2f", val))")
                }
            }

            // Find boosted top score
            let boostedTopIndex = boostedScores.enumerated().max(by: { $0.element < $1.element })!.offset
            var finalLabel = labels[boostedTopIndex]
            let finalScore = boostedScores[boostedTopIndex]

            // If boosted score > 1.0 and original label is low/medium, promote it
            if finalScore > 1.0 {
                let currentIndex = priorityOrder.firstIndex(of: finalLabel) ?? 0
                if currentIndex < priorityOrder.count - 1 {
                    finalLabel = priorityOrder[currentIndex + 1]
                    print(" Promoted priority due to boosted score > 1.0 → \(finalLabel)")
                }
            }

            print(" Final Prediction for '\(task.title)': \(finalLabel) with score \(String(format: "%.2f", finalScore))")
            return (finalLabel, finalScore)

        } catch {
            print(" Prediction failed for task: \(task.title). Error: \(error)")
            return nil
        }
    }

    // Return the top task found by priority rank and then ordering
    func topPriorityTask(from tasks: [TaskSample], contextProvider: (TaskSample) -> PredictionContext) -> TaskSample? {
        let priorityRank: [String: Int] = ["Low": 0, "Medium": 1, "High": 2] // Following priority ranks

        // score each task with model and its boost
        let scoredTasks = tasks.compactMap { task -> (task: TaskSample, label: String, score: Double)? in
            guard let result = predictWithScore(task: task, contextProvider: { contextProvider(task) }) else {
                return nil
            }

            return (task, result.label, result.score)
        }

        // sort by class rank first then by probability score
        // ensure a low 0.9 doesnt outrank a high 0.6
        guard let top = scoredTasks.sorted(by: { lhs, rhs in
            let lhsRank = priorityRank[lhs.label] ?? 0
            let rhsRank = priorityRank[rhs.label] ?? 0

            if lhsRank == rhsRank {
                return lhs.score > rhs.score
            }
            return lhsRank > rhsRank
        }).first else {
            print(" No top task could be selected.")
            return nil
        }

        print(" Top task selected: \(top.task.title) [Predicted: \(top.label), Score: \(String(format: "%.2f", top.score))]")
        return top.task
    }


}
