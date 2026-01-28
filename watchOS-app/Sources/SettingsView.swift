//
//  SettingsView.swift
//  Task Manager
//
//  Created by Dannie Watkins on 30/07/2025.
//

import SwiftUI
import CoreLocation

// Sheet view where the user can select which option they want to select
struct locationAndTaskSelector: View {
    let title: String
    let selections: [String]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text(title)
                .font(.headline) // Makes it bold
            List(selections, id: \ .self) { selections in
                Button(action: {
                    selected = selections // the selected option is the set option
                    dismiss()
                }) {
                    HStack {
                        Text(selections)
                        Spacer()
                        if selected == selections {
                            Image(systemName: "checkmark") // sets a checkmart to the selected option
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - SettingsView
struct PersonalisationView: View {
    @Binding var reloadMainView: UUID
    @AppStorage("selectedLocationMode") private var selectedLocationMode: String = LocationSwitcher.automatic.rawValue
    @AppStorage("favouredTaskType") private var favouredTaskType: String = FavourType.none.rawValue

    @State private var showingLocationSheet = false
    @State private var showingFavorSheet = false
    
    

    var body: some View {
        VStack(spacing: 16) {
            Text("Personalisation")
                .font(.title3)
                .bold()

            Button {
                showingLocationSheet = true
            } label: {
                HStack {
                    Image(systemName: LocationSwitcher(rawValue: selectedLocationMode)?.icon ?? "location")
                    VStack(alignment: .leading) {
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(selectedLocationMode)
                            .font(.body)
                            .bold()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()

            }

            Button {
                showingFavorSheet = true
            } label: {
                HStack {
                    Image(systemName: "star.circle")
                    VStack(alignment: .leading) {
                        Text("Task Priority")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(favouredTaskType)
                            .font(.body)
                            .bold()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()

            }
        }
        .padding()
        .sheet(isPresented: $showingLocationSheet) {
            locationAndTaskSelector(title: "Select Location", selections: LocationSwitcher.allCases.map { $0.rawValue }, selected: $selectedLocationMode)
        }
        .sheet(isPresented: $showingFavorSheet) {
            locationAndTaskSelector(title: "Favor Task Type", selections: FavourType.allCases.map { $0.rawValue }, selected: $favouredTaskType)
        }.onChange(of: favouredTaskType) {
            
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
            _ = classifier?.recomputeAndPersistAll(contextLocation: selectedLocationMode)
            reloadMainView = UUID()}
    }
}

#Preview {
    PersonalisationView(reloadMainView: .constant(UUID()))
}
