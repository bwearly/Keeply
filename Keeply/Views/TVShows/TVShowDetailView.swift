//
//  TVShowDetailView.swift
//  Keeply
//

import SwiftUI
import CoreData

struct TVShowDetailView: View {
    @Environment(\.managedObjectContext) private var context

    let show: TVShow

    @State private var isEditing = false

    @State private var editTitle: String = ""
    @State private var editYearText: String = ""
    @State private var editSeasonsText: String = ""
    @State private var editRating: Double = 0.0
    @State private var editNotes: String = ""
    @State private var editRewatch: Bool = false

    var body: some View {
        Form {
            headerSection
            detailsSection
        }
        .navigationTitle("TV Show")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing:
            Button(isEditing ? "Save" : "Edit") {
                if isEditing {
                    saveTVShow()
                    isEditing = false
                } else {
                    seedFields()
                    isEditing = true
                }
            }
        )
        .onAppear {
            seedFields()
        }
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                TVThumbIcon()

                VStack(alignment: .leading, spacing: 6) {
                    Text(isEditing ? editTitle : (show.title ?? "—"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    if show.year != 0 {
                        Text(String(show.year))
                            .foregroundStyle(.secondary)
                    }

                    Text(seasonsLabel(seasons: show.seasons))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            if isEditing {
                TextField("Title", text: $editTitle)

                TextField("Year", text: $editYearText)
                    .keyboardType(.numberPad)

                TextField("Seasons", text: $editSeasonsText)
                    .keyboardType(.numberPad)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Rating")
                        Spacer()
                        Text(ratingText(editRating))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $editRating, in: 0...10, step: 0.25)
                }
                .padding(.vertical, 6)

                Toggle("Rewatch", isOn: $editRewatch)

                TextEditor(text: $editNotes)
                    .frame(minHeight: 90)
            } else {
                row("Year", show.year == 0 ? "—" : String(show.year))
                row("Seasons", seasonsLabel(seasons: show.seasons))
                row("Rating", ratingText(show.rating))
                row("Rewatch", show.rewatch ? "Yes" : "No")

                if let n = show.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                        Text(n).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func ratingText(_ value: Double) -> String {
        if value == 0 { return "0/10" }
        return String(format: "%.2f/10", value)
    }

    private func seasonsLabel(seasons: Int16) -> String {
        if seasons == 0 { return "—" }
        return seasons == 1 ? "1 season" : "\(seasons) seasons"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func seedFields() {
        editTitle = show.title ?? ""
        editYearText = show.year == 0 ? "" : String(show.year)
        editSeasonsText = show.seasons == 0 ? "" : String(show.seasons)
        editRating = show.rating
        editNotes = show.notes ?? ""
        editRewatch = show.rewatch
    }

    private func saveTVShow() {
        show.title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let y = Int16(editYearText.trimmingCharacters(in: .whitespacesAndNewlines)), y > 0 {
            show.year = y
        } else {
            show.year = 0
        }

        if let s = Int16(editSeasonsText.trimmingCharacters(in: .whitespacesAndNewlines)), s > 0 {
            show.seasons = s
        } else {
            show.seasons = 0
        }

        show.rating = editRating
        show.rewatch = editRewatch

        let trimmed = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        show.notes = trimmed.isEmpty ? nil : trimmed

        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save TV show failed:", error)
        }
    }
}

private struct TVThumbIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))

            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 72, height: 96)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}
