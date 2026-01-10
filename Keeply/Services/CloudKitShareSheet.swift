//
//  CloudKitShareSheet.swift
//  Keeply
//

import SwiftUI
import CloudKit

struct CloudKitShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDone: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDone: onDone, onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        controller.presentationController?.delegate = context.coordinator
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
            finish()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(error)
            finish()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            finish()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            finish()
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { nil }
    }
}
