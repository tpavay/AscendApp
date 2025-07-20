//
//  HomeView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/17/25.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Home screen content")
            }
            .navigationTitle("Home Screen")
            .toolbar {
                HomeToolbarContent()
            }
        }

    }
}

#Preview {
    HomeView()
}
