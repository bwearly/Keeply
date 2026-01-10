//
//  CloudKitShareSheet.swift
//  Keeply
//

import SwiftUI
import CoreData
import CloudKit

struct CloudKitShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let persistentContainer: NSPersistentCloudKitContainer
    let onDone: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone, onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let container = CloudSharing.cloudKitContainer(from: persistentContainer)

        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        controller.presentationController?.delegate = context.coordinator

        print("ℹ️ CloudKit share UI presented (share provided):", share.recordID.recordName)
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
