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
        share: CKShare,
        persistentContainer: NSPersistentCloudKitContainer,
        onDone: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        Task { @MainActor in
            guard let presenter = TopMostViewController.find() else {
                onError(PresentationError.noPresenter)
                return
            }

            let container = CloudSharing.cloudKitContainer(from: persistentContainer)
            let controller = UICloudSharingController(share: share, container: container)
            controller.availablePermissions = [.allowReadOnly, .allowReadWrite]

            let coordinator = Coordinator(onDone: onDone, onError: onError)
            coordinator.attach(controller)
            controller.delegate = coordinator
            controller.presentationController?.delegate = coordinator

            objc_setAssociatedObject(
                controller,
                &AssociatedKeys.coordinator,
                coordinator,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )

            present(controller: controller, from: presenter, attempt: 0)
            print("ℹ️ CloudKit share UI presented (share provided):", share.recordID.recordName)
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
        case noPresenter

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

enum TopMostViewController {
    static func find() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return nil
        }

        let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        guard let root = window?.rootViewController else { return nil }
        return root.topMostViewController()
    }
}

private extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = presentedViewController {
            return presented.topMostViewController()
        }

        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController() ?? navigation
        }

        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? tab
        }

        return self
    }
}
