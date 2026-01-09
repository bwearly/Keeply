//
//  MovieDetailView.swift
//  Keeply
//

import SwiftUI
import CoreData

struct MovieDetailView: View {
    @Environment(\.managedObjectContext) private var context

    let movie: Movie
    let household: Household
    let member: HouseholdMember?

    // Single edit mode (details + feedback + watch history)
    @State private var isEditing = false

    // Loaded data (keeps SwiftUI body simple)
    @State private var members: [HouseholdMember] = []
    @State private var viewings: [Viewing] = []

    // Selected member for feedback
    @State private var selectedMember: HouseholdMember?

    // Movie edit fields
    @State private var editTitle: String = ""
    @State private var editYearText: String = ""
    @State private var editMPAA: String = "—"
    @State private var editMovieNotes: String = ""

    // Genres picker
    @State private var selectedGenres: Set<String> = []
    @State private var showGenrePicker = false

    private let allGenres: [String] = [
        "Action","Adventure","Animation","Comedy","Crime","Documentary","Drama","Family",
        "Fantasy","History","Horror","Music","Mystery","Romance","Sci-Fi","Thriller","War","Western"
    ]

    private var genresDisplay: String {
        selectedGenres.isEmpty ? "—" : selectedGenres.sorted().joined(separator: ", ")
    }

    // Feedback edit fields
    @State private var editRating: Double = 0.0
    @State private var editSlept: Bool = false
    @State private var editNotes: String = ""

    // Poster
    @State private var posterURL: URL?

    // Watch/rewatch draft notes
    @State private var viewingNotesDraft: String = ""

    var body: some View {
        Form {
            headerSection
            detailsSection
            feedbackSummarySection

            if isEditing {
                feedbackEditorSection
            }

            watchHistorySection
        }
        .navigationTitle("Movie")
        .navigationBarTitleDisplayMode(.inline)

        // Avoid `.toolbar` ambiguity
        .navigationBarItems(trailing:
            Button(isEditing ? "Save" : "Edit") {
                if isEditing {
                    saveAll()
                    isEditing = false
                    reloadAll()
                } else {
                    beginEditing()
                    isEditing = true
                }
            }
        )
        .navigationDestination(isPresented: $showGenrePicker) {
            GenrePickerView(title: "Select Genres", allGenres: allGenres, selected: $selectedGenres)
        }
        .onAppear {
            seedMovieEditorFieldsFromMovie()
            reloadAll()

            if selectedMember == nil {
                selectedMember = member ?? members.first
            }
        }
        .task {
            await ensurePosterLoaded()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                PosterLarge(title: movie.title, year: movie.year, posterURL: $posterURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text(isEditing ? editTitle : (movie.title ?? "—"))
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(movie.year == 0 ? "—" : String(movie.year))
                        .foregroundStyle(.secondary)

                    if let mpaa = movie.mpaaRating, !mpaa.isEmpty {
                        Text(mpaa)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
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

                Picker("MPAA Rating", selection: $editMPAA) {
                    ForEach(["—","G","PG","PG-13","R","NC-17","Not Rated"], id: \.self) { r in
                        Text(r).tag(r)
                    }
                }

                Button { showGenrePicker = true } label: {
                    HStack {
                        Text("Genres")
                        Spacer()
                        Text(genresDisplay)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                TextEditor(text: $editMovieNotes)
                    .frame(minHeight: 90)
            } else {
                row("MPAA", movie.mpaaRating ?? "—")
                row("Genres", (movie.genre ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : (movie.genre ?? "—"))

                if let n = movie.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes")
                        Text(n).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var feedbackSummarySection: some View {
        Section("Feedback Summary") {
            if members.isEmpty {
                Text("No members found.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members) { m in
                    summaryRow(for: m)
                }
            }
        }
    }

    private var feedbackEditorSection: some View {
        Section("Edit Feedback") {
            if members.isEmpty {
                Text("No members found.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Member", selection: Binding(
                    get: { selectedMember?.objectID },
                    set: { newID in
                        guard let newID else { return }
                        selectedMember = members.first(where: { $0.objectID == newID })
                        loadSelectedMemberFeedback()
                    }
                )) {
                    ForEach(members) { m in
                        Text(m.displayName ?? "Member").tag(Optional(m.objectID))
                    }
                }

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

                HStack {
                    Text("Fell asleep")
                    Spacer()
                    Toggle("", isOn: $editSlept).labelsHidden()
                }
                .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 90)
                        .overlay(alignment: .topLeading) {
                            if editNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Optional")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }
                        }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private var watchHistorySection: some View {
        Section("Watch History") {
            if viewings.isEmpty {
                Text("No watches recorded yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewings) { v in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewingDateText(v.watchedOn))
                                .font(.headline)

                            Text(v.isRewatch ? "Rewatch" : "Watched")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let n = v.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(n)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    guard isEditing else { return } // only delete while editing
                    deleteViewings(offsets: offsets)
                }
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Add")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Notes (optional)", text: $viewingNotesDraft)

                    HStack {
                        Button {
                            addViewing(isRewatch: false, notes: viewingNotesDraft)
                            viewingNotesDraft = ""
                        } label: {
                            Label("Watched", systemImage: "checkmark.circle")
                        }

                        Spacer()

                        Button {
                            addViewing(isRewatch: true, notes: viewingNotesDraft)
                            viewingNotesDraft = ""
                        } label: {
                            Label("Rewatch", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                }
                .padding(.top, 6)
            } else {
                Text("Tap Edit to add watches or rewatches.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Edit flow

    private func beginEditing() {
        seedMovieEditorFieldsFromMovie()

        if selectedMember == nil {
            selectedMember = member ?? members.first
        }
        loadSelectedMemberFeedback()
    }

    private func saveAll() {
        saveMovieDetails()
        saveSelectedMemberFeedback()
        reloadAll()
    }

    // MARK: - Reload data

    private func reloadAll() {
        reloadMembers()
        reloadViewings()
    }

    private func reloadMembers() {
        members = fetchedMembers()
        if selectedMember == nil {
            selectedMember = member ?? members.first
        }
    }

    private func reloadViewings() {
        let req = NSFetchRequest<Viewing>(entityName: "Viewing")
        req.predicate = NSPredicate(format: "movie == %@", movie)
        req.sortDescriptors = [NSSortDescriptor(key: "watchedOn", ascending: false)]
        viewings = (try? context.fetch(req)) ?? []
    }

    // MARK: - Movie details

    private func seedMovieEditorFieldsFromMovie() {
        editTitle = movie.title ?? ""
        editYearText = movie.year == 0 ? "" : String(movie.year)
        editMPAA = (movie.mpaaRating ?? "").isEmpty ? "—" : (movie.mpaaRating ?? "—")
        editMovieNotes = movie.notes ?? ""

        selectedGenres = Set((movie.genre ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )
    }

    private func saveMovieDetails() {
        movie.title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if let y = Int16(editYearText.trimmingCharacters(in: .whitespacesAndNewlines)), y > 0 {
            movie.year = y
        } else {
            movie.year = 0
        }

        movie.mpaaRating = (editMPAA == "—") ? nil : editMPAA
        movie.genre = selectedGenres.isEmpty ? nil : selectedGenres.sorted().joined(separator: ", ")

        let trimmed = editMovieNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        movie.notes = trimmed.isEmpty ? nil : trimmed

        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save movie details failed:", error)
            return
        }

        // Refresh poster after changing title/year
        Task {
            let fetched = await OMDbPosterService.posterURL(title: movie.title, year: movie.year)
            await MainActor.run {
                movie.posterURL = fetched?.absoluteString
                posterURL = fetched
                try? context.save()
            }
        }
    }

    // MARK: - Feedback

    private func loadSelectedMemberFeedback() {
        guard let selectedMember else { return }
        let fb = MovieFeedbackStore.getOrCreate(movie: movie, member: selectedMember, context: context)
        editRating = fb.rating
        editSlept = fb.slept
        editNotes = fb.notes ?? ""
    }

    private func saveSelectedMemberFeedback() {
        guard let selectedMember else { return }
        let fb = MovieFeedbackStore.getOrCreate(movie: movie, member: selectedMember, context: context)

        fb.rating = editRating
        fb.slept = editSlept
        fb.updatedAt = Date()

        let trimmed = editNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        fb.notes = trimmed.isEmpty ? nil : trimmed

        fb.household = household

        do {
            try context.save()
        } catch {
            context.rollback()
            print("Save feedback failed:", error)
        }
    }

    // MARK: - Viewing / Rewatch

    private func addViewing(isRewatch: Bool, notes: String?) {
        context.performAndWait {
            let v = Viewing(context: context)

            // Set required fields defensively
            if v.value(forKey: "id") == nil { v.setValue(UUID(), forKey: "id") }
            if v.value(forKey: "watchedOn") == nil { v.setValue(Date(), forKey: "watchedOn") }

            v.setValue(isRewatch, forKey: "isRewatch")
            v.setValue(movie, forKey: "movie")
            v.setValue(household, forKey: "household")

            let trimmed = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            v.setValue(trimmed.isEmpty ? nil : trimmed, forKey: "notes")

            do {
                try context.save()
                reloadViewings()
            } catch {
                context.rollback()
                print("❌ Failed to save viewing:", error)

                // This prints *why* validation failed (super helpful)
                let nsError = error as NSError
                if let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                    for e in detailed { print("•", e, e.userInfo) }
                } else {
                    print("•", nsError, nsError.userInfo)
                }
            }
        }
    }


    private func deleteViewings(offsets: IndexSet) {
        // Delete based on the same array SwiftUI rendered
        for index in offsets {
            guard viewings.indices.contains(index) else { continue }
            context.delete(viewings[index])
        }

        do {
            try context.save()
            reloadViewings()
        } catch {
            context.rollback()
            print("Failed to delete viewings:", error)
        }
    }

    private func viewingDateText(_ date: Date?) -> String {
        guard let date else { return "Unknown date" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Poster

    private func ensurePosterLoaded() async {
        if let s = movie.posterURL, !s.isEmpty, let url = URL(string: s) {
            posterURL = url
            return
        }

        let fetched = await OMDbPosterService.posterURL(title: movie.title, year: movie.year)
        posterURL = fetched

        if let fetched {
            await MainActor.run {
                movie.posterURL = fetched.absoluteString
                try? context.save()
            }
        }
    }

    // MARK: - Data helpers

    private func fetchedMembers() -> [HouseholdMember] {
        let req = NSFetchRequest<HouseholdMember>(entityName: "HouseholdMember")
        if let hid = household.id {
            req.predicate = NSPredicate(format: "household.id == %@", hid as CVarArg)
        } else {
            req.predicate = NSPredicate(format: "household == %@", household)
        }
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(req)) ?? []
    }

    private func fetchFeedback(movie: Movie, member: HouseholdMember) -> MovieFeedback? {
        let req = NSFetchRequest<MovieFeedback>(entityName: "MovieFeedback")
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "movie == %@ AND member == %@", movie, member)
        return try? context.fetch(req).first
    }

    // MARK: - UI helpers

    private func ratingText(_ value: Double) -> String {
        if value == 0 { return "0/10" }
        return String(format: "%.2f/10", value)
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

    private func summaryRow(for m: HouseholdMember) -> some View {
        let fb = fetchFeedback(movie: movie, member: m)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(m.displayName ?? "Member")
                    .font(.headline)
                Spacer()
                Text(ratingText(fb?.rating ?? 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let fb {
                HStack(spacing: 8) {
                    Text(fb.slept ? "Slept 😴" : "Stayed awake")
                    if let n = fb.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("•")
                        Text(n).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text("No feedback")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Poster Large

private struct PosterLarge: View {
    let title: String?
    let year: Int16
    @Binding var posterURL: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))

            if let posterURL {
                AsyncImage(url: posterURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "film")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 90, height: 130)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}
