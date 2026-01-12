//
//  AddTVShowView.swift
//  Keeply
//

import SwiftUI
import CoreData

struct AddTVShowView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household

    @State private var title: String = ""
    @State private var yearText: String = ""
    @State private var seasonsText: String = ""
    @State private var rating: Double = 0.0
    @State private var notes: String = ""
    @State private var rewatch: Bool = false

    var body: some View {
        Form {
            Section("TV Show") {
                TextField("Title", text: $title)

                TextField("Year", text: $yearText)
                    .keyboardType(.numberPad)

                TextField("Seasons", text: $seasonsText)
                    .keyboardType(.numberPad)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Rating")
                        Spacer()
                        Text(ratingText(rating))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $rating, in: 0...10, step: 0.25)
                }
                .padding(.vertical, 6)

                Toggle("Rewatch", isOn: $rewatch)

                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Notes (optional)")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
            }
        }
        .navigationTitle("Add TV Show")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveTVShow() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func ratingText(_ value: Double) -> String {
        if value == 0 { return "0/10" }
        return String(format: "%.2f/10", value)
    }

    private func saveTVShow() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let show = TVShow(context: context)
        show.id = UUID()
        show.createdAt = Date()
        show.title = trimmedTitle
        show.rewatch = rewatch
        show.rating = rating

        if let y = Int16(yearText.trimmingCharacters(in: .whitespacesAndNewlines)), y > 0 {
            show.year = y
        } else {
            show.year = 0
        }

        if let s = Int16(seasonsText.trimmingCharacters(in: .whitespacesAndNewlines)), s > 0 {
            show.seasons = s
        } else {
            show.seasons = 0
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        show.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        show.household = household

        if household.id == nil {
            household.id = UUID()
        }
        show.householdID = household.id

        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            print("Save TV show failed:", error)
        }
    }
}
