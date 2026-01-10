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
        let controller: UICloudSharingController
        if let preparedShare, preparedShare.url != nil {
            let currentTitle = preparedShare[CKShare.SystemFieldKey.title] as? String
            if currentTitle == nil || currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                preparedShare[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
            }
            onSharePrepared(preparedShare)
            controller = UICloudSharingController(
                share: preparedShare,
                container: CloudSharing.cloudKitContainer(from: persistentContainer)
            )
        } else {
            // Use a preparation handler so the controller owns the full share lifecycle.
            controller = UICloudSharingController { _, completion in
                Task { @MainActor in
                    do {
                        let household = try viewContext.existingObject(with: householdID) as! Household
                        let share = try await CloudSharing.fetchOrCreateShare(
                            for: household,
                            in: viewContext,
                            persistentContainer: persistentContainer
                        )

                        let currentTitle = share[CKShare.SystemFieldKey.title] as? String
                        if currentTitle == nil || currentTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                            share[CKShare.SystemFieldKey.title] = shareTitle as CKRecordValue
                        }

                        print("✅ CloudKit share ready:", share.recordID.recordName)
                        onSharePrepared(share)
                        completion(share, CloudSharing.cloudKitContainer(from: persistentContainer), nil)
                    } catch {
                        print("❌ CloudKit share preparation failed:", error)
                        onError(error)
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        controller.presentationController?.delegate = context.coordinator
        print("ℹ️ CloudKit share UI presented.")
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private let onDone: () -> Void
        private let onError: (Error) -> Void
        private var didFinish = false

        init(onDone: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onDone = onDone
            self.onError = onError
        }

        private func finish() {
            guard !didFinish else { return }
            didFinish = true
            DispatchQueue.main.async { self.onDone() }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            print("ℹ️ CloudKit share sheet dismissed.")
            finish()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("❌ CloudKit share failed to save:", error)
            onError(error)
            finish()
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
