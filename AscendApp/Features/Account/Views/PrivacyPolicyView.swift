//
//  PrivacyPolicyView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 2/19/26.
//

import SafariServices
import SwiftUI

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.preferredBarTintColor = UIColor(red: 0.043, green: 0.043, blue: 0.043, alpha: 1)
        safari.preferredControlTintColor = UIColor(red: 0.706, green: 0.8, blue: 0, alpha: 1)
        return safari
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
