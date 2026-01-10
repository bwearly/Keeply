//
//  CloudKitShareSheet.swift
//  Keeply
//

import SwiftUI
import CoreData
import CloudKit

struct CloudKitShareSheet: UIViewControllerRepresentable {
    let householdID: NSManagedObjectID
    let viewContext: NSManagedObjectContext
    let persistentContainer: NSPersistentCloudKitContainer
    let shareTitle: String
    let preparedShare: CKShare?
    let onSharePrepared: (CKShare) -> Void
    let onDone: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone, onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let container = CloudSharing.cloudKitContainer(from: persistentContainer)
        let controller = UICloudSharingController { _, completion in
            Task(priority: .userInitiated) {
                do {
                    let share: CKShare

                    if let preparedShare {
                        share = preparedShare
                        print("ℹ️ Reusing existing CloudKit share:", share.recordID.recordName, "url:", share.url as Any)
                    } else {
                        let household: Household = try await viewContext.perform {
                            guard let obj = try? viewContext.existingObject(with: householdID) as? Household else {
                                throw NSError(
                                    domain: "CloudKitShareSheet",
                                    code: 404,
                                    userInfo: [NSLocalizedDescriptionKey: "Household no longer exists."]
                                )
                            }
                            return obj
                        }

                        print("ℹ️ CloudSharing start for household:", household.objectID)

                        share = try await CloudSharing.fetchOrCreateShare(
                            for: household,
                            in: viewContext,
                            persistentContainer: persistentContainer
                        )

                        print("ℹ️ Created/fetched CloudKit share:", share.recordID.recordName, "url:", share.url as Any)
                    }

                    let currentTitle = share[CKShare.SystemFieldKey.title] as? String
                    if currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                        share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
                    }

                    await MainActor.run {
                        onSharePrepared(share)
                        completion(share, container, nil)
                    }
                } catch {
                    print("❌ CloudKit share preparation failed:", error)
                    await MainActor.run {
                        onError(error)
                        completion(nil, container, error)
                    }
                }
            }
        }

        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        print("ℹ️ CloudKit share UI presented (preparation handler).")
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onDone: () -> Void
        private let onError: (Error) -> Void
        private var didFinish = false

        init(onDone: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onDone = onDone
            self.onError = onError
        }

        private func finish(error: Error? = nil) {
            guard !didFinish else { return }
            didFinish = true

            if let error {
                onError(error)
            }
            onDone()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("❌ CloudKit share failed to save:", error)
            finish(error: error)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            print("✅ CloudKit share saved.")
            finish()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("🛑 CloudKit sharing stopped.")
            finish()
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Keeply Household"
        }
    }
}
