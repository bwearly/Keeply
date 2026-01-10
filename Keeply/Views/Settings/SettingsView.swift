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

    @State private var showShareSheet = false
    @State private var isSharing = false
    @State private var share: CKShare?
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var lastCloudKitError: String?
    @State private var shareTask: Task<Void, Never>?
    @State private var shareTimeoutTask: Task<Void, Never>?
    @State private var shareAttemptID = UUID()

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
        .onAppear { onAppearActions() }
        .onChange(of: household?.objectID) { _, _ in onHouseholdChange() }
        .sheet(isPresented: $showShareSheet) { shareSheet }
    }

    // MARK: - Extracted Sections

    @ViewBuilder
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
                        if isSharing { ProgressView() }
                    }
                }
                .disabled(isSharing)
            } else {
                Text("You’re not in a household yet.")
                    .foregroundStyle(.secondary)

                TextField("Household name", text: $householdName)
                    .textInputAutocapitalization(.words)

                TextField("Your name", text: $myName)
                    .textInputAutocapitalization(.words)

                Button("Create Household") { createHousehold() }
                    .disabled(householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var shareStatusSection: some View {
        if let household {
            Section("Share Status") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(share == nil ? "Not shared" : "Shared")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Title")
                    Spacer()
                    Text(shareTitle(for: household))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("Invite link")
                    Spacer()
                    Text(share?.url == nil ? "Not ready" : "Ready")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var membersSection: some View {
        Section("Members") {
            if let household {
                let members = fetchMembers(for: household)
                if members.isEmpty {
                    Text("No members found (auto-fixing…)").foregroundStyle(.secondary)
                } else {
                    ForEach(members) { m in
                        HStack {
                            Text(m.displayName ?? "Member")
                            Spacer()
                            if m.objectID == member?.objectID {
                                Text("You").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Create a household to see members.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var howSharingWorksSection: some View {
        Section("How sharing works") {
            Text("Invites use iCloud sharing. Everyone in the household sees the same movies, feedback, and watch history.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sharingErrorSection: some View {
        if let shareErrorText {
            Section("Sharing Error") {
                Text(shareErrorText).foregroundStyle(.red)
                Button("Retry Invite") { inviteMember() }
                    .disabled(isSharing || household == nil)
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorText {
            Section("Error") {
                Text(errorText).foregroundStyle(.red)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            HStack {
                Text("iCloud status")
                Spacer()
                Text(accountStatusText(accountStatus))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Container")
                Spacer()
                Text(CloudSharing.containerIdentifier(from: persistentContainer))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Last CloudKit error")
                Spacer()
                Text(lastCloudKitError ?? "None")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
    #endif

    // MARK: - Sheet Content & Lifecycle Hooks

    @ViewBuilder
    private var shareSheet: some View {
        if let household, let share {
            CloudKitShareSheet(
                householdID: household.objectID,
                viewContext: context,
                persistentContainer: persistentContainer,
                shareTitle: shareTitle(for: household),
                preparedShare: share,
                onSharePrepared: { preparedShare in
                    self.share = preparedShare
                },
                onDone: {
                    showShareSheet = false
                    isSharing = false
                    reloadShareStatus()
                },
                onError: { error in
                    shareErrorText = error.localizedDescription
                    lastCloudKitError = error.localizedDescription
                    isSharing = false
                    showShareSheet = false
                }
            )
        }
    }

    private func onAppearActions() {
        if let hh = household { ensureDefaultMemberExists(in: hh) }
        reloadShareStatus()
        loadAccountStatus()
    }

    private func onHouseholdChange() {
        if let hh = household { ensureDefaultMemberExists(in: hh) }
        reloadShareStatus()
    }

    // MARK: - Share handling

    private func inviteMember() {
        guard let household else { return }
        guard shareTask == nil else { return }
        shareErrorText = nil
        isSharing = true
        shareAttemptID = UUID()
        let attemptID = shareAttemptID
        print("ℹ️ Preparing CloudKit share for household:", household.objectID)

        shareTimeoutTask?.cancel()
        shareTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard isSharing, shareAttemptID == attemptID else { return }
                shareErrorText = "Invite is taking too long. Check iCloud and try again."
                isSharing = false
                showShareSheet = false
                shareTask?.cancel()
                shareTask = nil
            }
        }

        shareTask = Task {
            do {
                let preparedShare = try await CloudSharing.fetchOrCreateShare(
                    for: household,
                    in: context,
                    persistentContainer: persistentContainer
                )
                await MainActor.run {
                    guard shareAttemptID == attemptID else { return }
                    share = preparedShare
                    isSharing = false
                    showShareSheet = true
                    shareTask = nil
                    shareTimeoutTask?.cancel()
                    shareTimeoutTask = nil
                }
            } catch {
                await MainActor.run {
                    guard shareAttemptID == attemptID else { return }
                    shareErrorText = error.localizedDescription
                    lastCloudKitError = error.localizedDescription
                    isSharing = false
                    showShareSheet = false
                    shareTask = nil
                    shareTimeoutTask?.cancel()
                    shareTimeoutTask = nil
                }
            }
        }
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
            NSSortDescriptor(key: "displayName", ascending: true,
                             selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
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

