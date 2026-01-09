//
//  SettingsView.swift
//  Keeply
//

import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @Binding var household: Household?
    @Binding var member: HouseholdMember?

    @State private var errorText: String?

    @State private var householdName = ""
    @State private var myName = ""

    @State private var showInvite = false

    var body: some View {
        Form {
            Section("Household") {
                if let household {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(household.name ?? "Household")
                            .font(.headline)

                        Text("Sharing uses iCloud")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Button("Invite People") {
                        showInvite = true
                    }
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

            Section("How sharing works") {
                Text("Invites use iCloud sharing. Everyone in the household sees the same movies, feedback, and watch history.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Section("Error") {
                    Text(errorText).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            if let hh = household { ensureDefaultMemberExists(in: hh) }
        }
        .onChange(of: household?.objectID) { _, _ in
            if let hh = household { ensureDefaultMemberExists(in: hh) }
        }
        .sheet(isPresented: $showInvite) {
            if let hh = household {
                HouseholdInviteLinkView(
                    household: hh,
                    onDone: { showInvite = false },
                    onError: { msg in
                        errorText = msg
                        showInvite = false
                    }
                )
                .ignoresSafeArea()
            }
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
