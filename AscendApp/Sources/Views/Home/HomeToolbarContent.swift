//
//  HomeToolbarView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/19/25.
//

import SwiftUI

struct HomeToolbarContent: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem {
            NavigationLink(destination: AccountView()) {
                Image(systemName: "person")
            }
        }
    }
}
