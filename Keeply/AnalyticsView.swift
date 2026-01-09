//
//  AnalyticsView.swift
//  Keeply
//
//  Created by Blake Early on 1/8/26.
//

import SwiftUI
import CoreData

struct AnalyticsView: View {
    @Environment(\.managedObjectContext) private var context

    let household: Household
    let member: HouseholdMember?   // current user (optional)

    // UI state
    @State private var members: [HouseholdMember] = []
    @State private var selectedMemberID: NSManagedObjectID? = nil // nil = all household

    // Computed data
    @State private var totalMovies: Int = 0
    @State private var totalViewings: Int = 0
    @State private var totalRewatches: Int = 0

    @State private var avgRating: Double = 0
    @State private var ratingCount: Int = 0

    @State private var sleptCount: Int = 0
    @State private var feedbackCount: Int = 0

    @State private var topGenres: [(String, Int)] = []
    @State private var topRatedMovies: [(Movie, Double, Int)] = [] // movie, avg, count

    private var selectedMember: HouseholdMember? {
        guard let selectedMemberID else { return nil }
        return members.first(where: { $0.objectID == selectedMemberID })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCards
                pickerCard
                ratingsCard
                sleepCard
                genresCard
                topRatedCard
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadAll()
            if selectedMemberID == nil, let member {
                // selectedMemberID = member.objectID
            }
        }
        .onChange(of: selectedMemberID) { _, _ in
            reloadAll()
        }
    }

    // MARK: - UI pieces

    private var headerCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatCard(title: "Movies", value: "\(totalMovies)")
                StatCard(title: "Watches", value: "\(totalViewings)")
            }
            HStack(spacing: 10) {
                StatCard(title: "Rewatches", value: "\(totalRewatches)")
                StatCard(
                    title: selectedMember == nil ? "House Avg" : "My Avg",
                    value: ratingCount == 0 ? "—" : String(format: "%.1f", avgRating)
                )
            }
        }
    }

    private var pickerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Filter")
                    .font(.headline)

                Picker("Member", selection: $selectedMemberID) {
                    Text("All Household").tag(Optional<NSManagedObjectID>.none)
                    ForEach(members) { m in
                        Text(m.displayName ?? "Member").tag(Optional(m.objectID))
                    }
                }
                .pickerStyle(.menu)

                Text(selectedMember == nil ? "Showing household-wide stats." : "Showing stats for \(selectedMember?.displayName ?? "Member").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ratingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ratings")
                    .font(.headline)

                HStack {
                    Text("Average")
                    Spacer()
                    Text(ratingCount == 0 ? "—" : "\(String(format: "%.2f", avgRating))/10")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Ratings count")
                    Spacer()
                    Text("\(ratingCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var sleepCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep")
                    .font(.headline)

                HStack {
                    Text("Feedback entries")
                    Spacer()
                    Text("\(feedbackCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Slept through")
                    Spacer()
                    Text("\(sleptCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Text("Sleep rate")
                    Spacer()
                    Text(feedbackCount == 0 ? "—" : "\(Int((Double(sleptCount) / Double(feedbackCount)) * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var genresCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top Genres")
                    .font(.headline)

                if topGenres.isEmpty {
                    Text("No genres yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(topGenres.prefix(8), id: \.0) { g, c in
                        HStack {
                            Text(g)
                            Spacer()
                            Text("\(c)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private var topRatedCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Top Rated Movies")
                    .font(.headline)

                if topRatedMovies.isEmpty {
                    Text("No rated movies yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(Array(topRatedMovies.prefix(10).enumerated()), id: \.offset) { idx, item in
                        let (movie, avg, count) = item
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(movie.title ?? "Untitled")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text(movie.year == 0 ? "—" : "\(movie.year)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.1f", avg))
                                    .font(.subheadline)
                                    .monospacedDigit()
                                Text("(\(count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        if idx != min(topRatedMovies.count, 10) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reload

    private func reloadAll() {
        reloadMembers()
        reloadTotals()
        reloadRatings()
        reloadSleep()
        reloadGenres()
        reloadTopRated()
    }

    private func reloadMembers() {
        let req = NSFetchRequest<HouseholdMember>(entityName: "HouseholdMember")
        if let hid = household.id {
            req.predicate = NSPredicate(format: "household.id == %@", hid as CVarArg)
        } else {
            req.predicate = NSPredicate(format: "household == %@", household)
        }
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        members = (try? context.fetch(req)) ?? []
    }

    private func reloadTotals() {
        // Movies
        let movieReq = NSFetchRequest<Movie>(entityName: "Movie")
        if let hid = household.id {
            movieReq.predicate = NSPredicate(format: "householdID == %@", hid as CVarArg)
        } else {
            movieReq.predicate = NSPredicate(format: "household == %@", household)
        }
        totalMovies = (try? context.count(for: movieReq)) ?? 0

        // Viewings
        let viewingReq = NSFetchRequest<Viewing>(entityName: "Viewing")
        viewingReq.predicate = NSPredicate(format: "household == %@", household)
        totalViewings = (try? context.count(for: viewingReq)) ?? 0

        let rewatchReq = NSFetchRequest<Viewing>(entityName: "Viewing")
        rewatchReq.predicate = NSPredicate(format: "household == %@ AND isRewatch == YES", household)
        totalRewatches = (try? context.count(for: rewatchReq)) ?? 0
    }

    private func reloadRatings() {
        // ✅ IMPORTANT: dictionaryResultType must NOT use NSFetchRequest<MovieFeedback>
        let req = NSFetchRequest<NSDictionary>(entityName: "MovieFeedback")

        if let m = selectedMember {
            req.predicate = NSPredicate(format: "household == %@ AND member == %@ AND rating > 0", household, m)
        } else {
            req.predicate = NSPredicate(format: "household == %@ AND rating > 0", household)
        }

        req.resultType = .dictionaryResultType

        let avgExpr = NSExpressionDescription()
        avgExpr.name = "avgRating"
        avgExpr.expression = NSExpression(forFunction: "average:", arguments: [NSExpression(forKeyPath: "rating")])
        avgExpr.expressionResultType = .doubleAttributeType

        let countExpr = NSExpressionDescription()
        countExpr.name = "countRating"
        countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "rating")])
        countExpr.expressionResultType = .integer64AttributeType

        req.propertiesToFetch = [avgExpr, countExpr]
        req.fetchLimit = 1

        do {
            let dict = try context.fetch(req).first
            avgRating = (dict?.object(forKey: "avgRating") as? Double) ?? 0
            ratingCount = Int((dict?.object(forKey: "countRating") as? Int64) ?? 0)
        } catch {
            avgRating = 0
            ratingCount = 0
        }
    }

    private func reloadSleep() {
        let req = NSFetchRequest<MovieFeedback>(entityName: "MovieFeedback")

        if let m = selectedMember {
            req.predicate = NSPredicate(format: "household == %@ AND member == %@", household, m)
        } else {
            req.predicate = NSPredicate(format: "household == %@", household)
        }

        do {
            let all = try context.fetch(req)
            feedbackCount = all.count
            sleptCount = all.filter { $0.slept }.count
        } catch {
            feedbackCount = 0
            sleptCount = 0
        }
    }

    private func reloadGenres() {
        let req = NSFetchRequest<Movie>(entityName: "Movie")
        if let hid = household.id {
            req.predicate = NSPredicate(format: "householdID == %@", hid as CVarArg)
        } else {
            req.predicate = NSPredicate(format: "household == %@", household)
        }

        let movies = (try? context.fetch(req)) ?? []
        var counts: [String: Int] = [:]

        for m in movies {
            let parts = (m.genre ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            for g in parts {
                counts[g, default: 0] += 1
            }
        }

        topGenres = counts
            .map { ($0.key, $0.value) }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                return a.0.localizedCaseInsensitiveCompare(b.0) == .orderedAscending
            }
    }

    private func reloadTopRated() {
        let movieReq = NSFetchRequest<Movie>(entityName: "Movie")
        if let hid = household.id {
            movieReq.predicate = NSPredicate(format: "householdID == %@", hid as CVarArg)
        } else {
            movieReq.predicate = NSPredicate(format: "household == %@", household)
        }
        let movies = (try? context.fetch(movieReq)) ?? []

        var results: [(Movie, Double, Int)] = []

        for movie in movies {
            // ✅ IMPORTANT: dictionaryResultType must NOT use NSFetchRequest<MovieFeedback>
            let fbReq = NSFetchRequest<NSDictionary>(entityName: "MovieFeedback")

            if let m = selectedMember {
                fbReq.predicate = NSPredicate(format: "movie == %@ AND member == %@ AND rating > 0", movie, m)
            } else {
                fbReq.predicate = NSPredicate(format: "movie == %@ AND rating > 0", movie)
            }

            fbReq.resultType = .dictionaryResultType
            fbReq.fetchLimit = 1

            let avgExpr = NSExpressionDescription()
            avgExpr.name = "avgRating"
            avgExpr.expression = NSExpression(forFunction: "average:", arguments: [NSExpression(forKeyPath: "rating")])
            avgExpr.expressionResultType = .doubleAttributeType

            let countExpr = NSExpressionDescription()
            countExpr.name = "countRating"
            countExpr.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "rating")])
            countExpr.expressionResultType = .integer64AttributeType

            fbReq.propertiesToFetch = [avgExpr, countExpr]

            if let dict = try? context.fetch(fbReq).first {
                let avg = (dict.object(forKey: "avgRating") as? Double) ?? 0
                let count = Int((dict.object(forKey: "countRating") as? Int64) ?? 0)
                if count > 0 {
                    results.append((movie, avg, count))
                }
            }
        }

        topRatedMovies = results.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return (a.0.title ?? "").localizedCaseInsensitiveCompare(b.0.title ?? "") == .orderedAscending
        }
    }
}

// MARK: - Small UI component

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
