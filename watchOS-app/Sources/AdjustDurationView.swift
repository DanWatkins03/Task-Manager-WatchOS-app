//
//  AdjustDurationView.swift
//  Task Manager
//
//  Created by Dannie Watkins
//

import SwiftUI


struct AdjustDurationView: View {
    @Binding var task: TaskSample
    @Environment(\.presentationMode) var presentationMode
    @State private var suggestedDuration: Double

    init(task: Binding<TaskSample>) {
        _task = task
        _suggestedDuration = State(initialValue: task.wrappedValue.duration * 0.85) 
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("“\(task.title)” has been completed faster than usual.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            Text("Would you like to reduce its duration?")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .foregroundColor(.gray)

            HStack {
                Text("Current:")
                Spacer()
                Text("\(task.duration, specifier: "%.1f") hrs")
            }

            HStack {
                Text("Suggested:")
                Spacer()
                Text("\(suggestedDuration, specifier: "%.1f") hrs")
                    .foregroundColor(.orange)
            }

            HStack(spacing: 12) {
                Button("Keep Duration") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.bordered)

                Button("Apply Change") {
                    task.duration = suggestedDuration
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}



struct AdjustDurationView_Previews: PreviewProvider {
    @State static var sampleTask = TaskSample(
        taskType: "Work",
        dateTime: Date(),
        duration: 1.5,
        location: "Work",
        title: "Prepare Brief",
        description: "Prepare notes before call",
        priority: "Medium"
    )

    static var previews: some View {
        NavigationStack {
            AdjustDurationView(task: $sampleTask)
        }
    }
}
