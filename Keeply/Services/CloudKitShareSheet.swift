//
//  CloudKitShareSheet.swift
//  Keeply
//

import UIKit
import CoreData
import CloudKit
import ObjectiveC

enum CloudKitSharePresenter {

    static func present(
        householdID: NSManagedObjectID,
        presenter: UIViewController,
        viewContext: NSManagedObjectContext,
        persistentContainer: NSPersistentCloudKitContainer,
        shareTitle: String,
        preparedShare: CKShare?,
        onSharePrepared: @escaping (CKShare) -> Void,
        onDone: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task { @MainActor in
            guard presenter.view.window != nil else {
                onError(PresentationError.presenterNotReady)
                return
            }

            let container = CloudSharing.cloudKitContainer(from: persistentContainer)

            let coordinator = Coordinator(onDone: onDone, onError: onError)
            let controller = UICloudSharingController { _, completion in
                // IMPORTANT: do NOT require share.url to exist here.
                // UICloudSharingController will save/prepare the share and generate the URL as needed.
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
                                        domain: "CloudKitSharePresenter",
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

                        // Ensure title
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

            coordinator.attach(controller)
            controller.delegate = coordinator
            controller.presentationController?.delegate = coordinator

            // Retain coordinator for lifetime of controller
            objc_setAssociatedObject(
                controller,
                &AssociatedKeys.coordinator,
                coordinator,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            present(controller: controller, from: presenter, attempt: 0)
            print("ℹ️ CloudKit share UI presented (preparation handler).")
        }
    }

    @MainActor
    private static func present(
        controller: UICloudSharingController,
        from presenter: UIViewController,
        attempt: Int
    ) {
        if attempt >= 10 {
            presenter.present(controller, animated: true)
            return
        }

        guard presenter.view.window != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                Task { @MainActor in
                    present(controller: controller, from: presenter, attempt: attempt + 1)
                }
            }
            return
        }

        presenter.present(controller, animated: true)
    }

    private enum AssociatedKeys {
        static var coordinator = UInt8(0)
    }

    private enum PresentationError: LocalizedError {
        case presenterNotReady
        var errorDescription: String? {
            "Unable to find an active window to present the share sheet."
        }
    }

    private final class Coordinator: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private let onDone: () -> Void
        private let onError: (Error) -> Void
        private var didFinish = false
        private weak var controller: UICloudSharingController?

        init(onDone: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onDone = onDone
            self.onError = onError
        }

        func attach(_ controller: UICloudSharingController) {
            self.controller = controller
        }

        private func finish(with error: Error? = nil) {
            guard !didFinish else { return }
            didFinish = true

            if let error {
                onError(error)
            }

            guard let controller else {
                onDone()
                return
            }

            controller.dismiss(animated: true) {
                self.onDone()
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            print("ℹ️ CloudKit share sheet dismissed.")
            finish()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("❌ CloudKit share failed to save:", error)
            finish(with: error)
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
