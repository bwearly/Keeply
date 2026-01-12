//
//  TVShowsListView.swift
//  Keeply
//

import SwiftUI
import CoreData

struct TVShowsListView: View {
    @Environment(\.managedObjectContext) private var context

    let household: Household

    @FetchRequest private var shows: FetchedResults<TVShow>

    @State private var showingAdd = false
    @State private var searchText = ""

    private enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case titleAZ = "Title A–Z"
        case yearNewOld = "Year (new→old)"
        case ratingHighLow = "Rating (high→low)"

        var id: String { rawValue }
    }
    @State private var sort: SortOption = .newest

    init(household: Household) {
        self.household = household

        let sort = [NSSortDescriptor(keyPath: \TVShow.createdAt, ascending: false)]

        if household.id == nil {
            household.id = UUID()
            try? household.managedObjectContext?.save()
        }

        _shows = FetchRequest<TVShow>(
            sortDescriptors: sort,
            predicate: NSPredicate(format: "householdID == %@", household.id! as CVarArg),
            animation: .default
        )
    }

    private var filteredShows: [TVShow] {
        var list = Array(shows)

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { show in
                let title = (show.title ?? "").lowercased()
                let year = show.year == 0 ? "" : String(show.year)
                return title.contains(q) || year.contains(q)
            }
        }

        switch sort {
        case .newest:
            list.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        case .oldest:
            list.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        case .titleAZ:
            list.sort { ($0.title ?? "").localizedCaseInsensitiveCompare($1.title ?? "") == .orderedAscending }
        case .yearNewOld:
            list.sort { $0.year > $1.year }
        case .ratingHighLow:
            list.sort { $0.rating > $1.rating }
        }

        return list
    }

    var body: some View {
        List {
            if filteredShows.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No TV shows yet" : "No results",
                    systemImage: "tv"
                )
            } else {
                ForEach(filteredShows) { show in
                    NavigationLink {
                        TVShowDetailView(show: show)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            TVThumbSmall()

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(show.title ?? "Untitled")
                                        .font(.headline)
                                        .lineLimit(1)

                                    Spacer()

                                    if show.rating > 0 {
                                        Text(ratingText(show.rating))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text(show.year == 0 ? "—" : String(show.year))
                                    Text("•")
                                    Text(seasonsLabel(seasons: show.seasons))
                                }
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                                if show.rewatch {
                                    Text("Rewatch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .onDelete(perform: deleteShows)
            }
        }
        .navigationTitle("TV Shows")
        .searchable(text: $searchText, prompt: "Search title or year…")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAdd = true } label: {
                    Label("Add TV Show", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddTVShowView(household: household)
            }
        }
    }

    private func deleteShows(offsets: IndexSet) {
        let toDelete = offsets.map { filteredShows[$0] }
        toDelete.forEach(context.delete)
        save()
    }

    private func save() {
        do { try context.save() }
        catch { print("Save failed:", error) }
    }

    private func ratingText(_ value: Double) -> String {
        if value == 0 { return "0/10" }
        return String(format: "%.2f/10", value)
    }

    private func seasonsLabel(seasons: Int16) -> String {
        if seasons == 0 { return "—" }
        return seasons == 1 ? "1 season" : "\(seasons) seasons"
    }
}

private struct TVThumbSmall: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))

            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 54, height: 80)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator), lineWidth: 0.5))
    }
}
