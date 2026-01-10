//
//  SettingsView.swift
//  Keeply
//

import SwiftUI
import CoreData
import CloudKit

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @Binding var household: Household?
    @Binding var member: HouseholdMember?

    @State private var errorText: String?
    @State private var shareErrorText: String?

    @State private var householdName = ""
    @State private var myName = ""

    @State private var isSharing = false
    @State private var showShareSheet = false
    @State private var share: CKShare?
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var lastCloudKitError: String?
    @State private var shareTimeoutTask: Task<Void, Never>?

    private let persistentContainer = PersistenceController.shared.container

    var body: some View {
        Form {
            householdSection
            shareStatusSection
            membersSection
            howSharingWorksSection
            sharingErrorSection
            errorSection
            #if DEBUG
            debugSection
            #endif
        }
        .navigationTitle("Settings")
        .onAppear {
            if let hh = household { ensureDefaultMemberExists(in: hh) }
            reloadShareStatus()
            loadAccountStatus()
        }
        .onChange(of: household?.objectID) { _, _ in
            if let hh = household { ensureDefaultMemberExists(in: hh) }
            reloadShareStatus()
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            if isSharing {
                isSharing = false
            }
        }) {
            if let household {
                CloudKitShareSheet(
                    householdID: household.objectID,
                    viewContext: context,
                    persistentContainer: persistentContainer,
                    shareTitle: shareTitle(for: household),
                    preparedShare: share,
                    onSharePrepared: { preparedShare in
                        shareTimeoutTask?.cancel()
                        shareTimeoutTask = nil
                        share = preparedShare
                    },
                    onDone: {
                        shareTimeoutTask?.cancel()
                        shareTimeoutTask = nil
                        isSharing = false
                        showShareSheet = false
                        reloadShareStatus()
                    },
                    onError: { error in
                        handleShareError(error)
                        showShareSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Sections

    private var householdSection: some View {
        Section("Household") {
            if let household {
                VStack(alignment: .leading, spacing: 6) {
                    Text(household.name ?? "Household")
                        .font(.headline)

                    Text("Sharing uses iCloud")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }

                Button {
                    inviteMember()
                } label: {
                    HStack {
                        Text(isSharing ? "Preparing invite..." : "Invite Member")
                        Spacer()
                        if isSharing {
                            ProgressView()
                        } else {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
                .disabled(isSharing)
            } else {
                Text("Create a household to begin.")
                    .foregroundStyle(.secondary)

                TextField("Household name", text: $householdName)
                TextField("Your name (optional)", text: $myName)

                Button("Create Household") {
                    createHousehold()
                }
                .disabled(householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var shareStatusSection: some View {
        Section("Share Status") {
            HStack {
                Text("iCloud account")
                Spacer()
                Text(accountStatusText(accountStatus))
                    .foregroundStyle(.secondary)
            }

            if let share {
                HStack {
                    Text("Share created")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                let title = (share[CKShare.SystemFieldKey.title] as? String) ?? ""
                if !title.isEmpty {
                    HStack {
                        Text("Share title")
                        Spacer()
                        Text(title)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack {
                    Text("Share created")
                    Spacer()
                    Text("Not yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var membersSection: some View {
        Section("Members") {
            if let household {
                let members = fetchMembers(for: household)
                if members.isEmpty {
                    ContentUnavailableView("No members yet", systemImage: "person.3")
                } else {
                    ForEach(members) { m in
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayName ?? "Unnamed")
                                    .font(.body)
                                if m == member {
                                    Text("You")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                    }
                }
            } else {
                Text("Create a household to add members.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var howSharingWorksSection: some View {
        Section("How sharing works") {
            Text("Inviting someone creates a private iCloud share for this household. Anyone you invite can see the same household data on their device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var sharingErrorSection: some View {
        Section("Sharing") {
            if let shareErrorText {
                Text(shareErrorText)
                    .foregroundStyle(.red)
                    .font(.footnote)
            } else {
                Text("No sharing errors.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
    }

    private var errorSection: some View {
        Section {
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            HStack {
                Text("Account status")
                Spacer()
                Text(accountStatusText(accountStatus))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Last CloudKit error")
                Spacer()
                Text(lastCloudKitError ?? "None")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button("Reload share status") {
                reloadShareStatus()
            }
        }
    }
    #endif

    // MARK: - Share handling

    private func inviteMember() {
        guard let household else { return }

        shareErrorText = nil
        lastCloudKitError = nil

        isSharing = true
        showShareSheet = true

        print("ℹ️ Preparing CloudKit share for household:", household.objectID)

        shareTimeoutTask?.cancel()
        shareTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isSharing else { return }
                shareErrorText = "Invite is taking too long. Check iCloud and try again."
                lastCloudKitError = shareErrorText
                isSharing = false
            }
        }
    }

    @MainActor
    private func handleShareError(_ error: Error) {
        shareTimeoutTask?.cancel()
        shareTimeoutTask = nil
        shareErrorText = error.localizedDescription
        lastCloudKitError = error.localizedDescription
        isSharing = false
    }

    private func reloadShareStatus() {
        guard let household else {
            share = nil
            return
        }

        share = (try? CloudSharing.fetchShare(
            for: household.objectID,
            persistentContainer: persistentContainer
        ))
    }

    private func loadAccountStatus() {
        Task {
            let status = await CloudSharing.accountStatus(using: persistentContainer)
            await MainActor.run { accountStatus = status }
        }
    }

    private func shareTitle(for household: Household) -> String {
        if let shareTitle = share?[CKShare.SystemFieldKey.title] as? String, !shareTitle.isEmpty {
            return shareTitle
        }
        return household.name ?? "Household"
    }

    private func accountStatusText(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "Available"
        case .noAccount: return "No account"
        case .restricted: return "Restricted"
        case .couldNotDetermine: return "Could not determine"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Members (RELIABLE FETCH)

    private func fetchMembers(for household: Household) -> [HouseholdMember] {
        let req: NSFetchRequest<HouseholdMember> = HouseholdMember.fetchRequest()
        req.predicate = NSPredicate(format: "household == %@", household)
        req.sortDescriptors = [
            NSSortDescriptor(
                key: "displayName",
                ascending: true,
                selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
            )
        ]

        do {
            return try context.fetch(req)
        } catch {
            print("Fetch members failed:", error)
            return []
        }
    }

    private func ensureDefaultMemberExists(in household: Household) {
        let members = fetchMembers(for: household)

        if !members.isEmpty {
            if self.member == nil {
                self.member = members.first
                SelectionStore.save(household: self.household, member: self.member)
            }
            return
        }

        let me = HouseholdMember(context: context)
        me.id = UUID()
        me.createdAt = Date()
        me.displayName = "Me"
        me.household = household

        do {
            try context.save()
            self.member = me
            SelectionStore.save(household: self.household, member: self.member)
        } catch {
            context.rollback()
            self.errorText = error.localizedDescription
        }
    }

    // MARK: - Create Household

    private func createHousehold() {
        errorText = nil

        let hhName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hhName.isEmpty else { return }

        let name = myName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "Me" : name

        let hh = Household(context: context)
        hh.id = UUID()
        hh.createdAt = Date()
        hh.name = hhName

        let me = HouseholdMember(context: context)
        me.id = UUID()
        me.createdAt = Date()
        me.displayName = displayName
        me.household = hh

        do {
            try context.save()
            self.household = hh
            self.member = me
            SelectionStore.save(household: hh, member: me)

            householdName = ""
            myName = ""
        } catch {
            context.rollback()
            self.errorText = error.localizedDescription
        }
    }
}
