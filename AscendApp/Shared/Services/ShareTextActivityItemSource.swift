//
//  ShareTextActivityItemSource.swift
//  AscendApp
//
//  Created by Tyler Pavay on 10/5/25.
//

import UIKit

final class ShareTextActivityItemSource: NSObject, UIActivityItemSource {
    private let text: String

    init(text: String) {
        self.text = text
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any {
        if activityType == .copyToPasteboard {
            return ""
        }
        return text
    }
}
