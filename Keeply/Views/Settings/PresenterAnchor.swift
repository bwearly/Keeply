//
//  PresenterAnchor.swift
//  Keeply
//

import SwiftUI
import UIKit

final class PresenterHolder {
    weak var window: UIWindow?
}

struct PresenterAnchor: UIViewControllerRepresentable {
    let holder: PresenterHolder

    func makeUIViewController(context: Context) -> UIViewController {
        AnchorViewController(holder: holder)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        holder.window = uiViewController.view.window
    }

    private final class AnchorViewController: UIViewController {
        private let holder: PresenterHolder

        init(holder: PresenterHolder) {
            self.holder = holder
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            holder.window = view.window
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            holder.window = view.window
        }
    }
}
