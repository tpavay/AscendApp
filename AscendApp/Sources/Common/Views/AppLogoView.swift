//
//  AppLogoView.swift
//  AscendApp
//
//  Created by Tyler Pavay on 7/13/25.
//

import SwiftUI

struct AppLogoView: View {
    var showTagline: Bool = true
    
    var body: some View {
        VStack(spacing: 8) {
            // Option 2: If you want to use your app icon
             Image("AppIconInternal")
                 .resizable()
                 .scaledToFit()
                 .frame(width: 80, height: 80)
                 .cornerRadius(16)

            // Option 1: Text-based logo
            Text("Ascend")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if showTagline {
                Text("Track your climb to greatness")
                    .font(.headline)
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        AppLogoView(showTagline: true)
        AppLogoView(showTagline: false)
    }
    .padding()
    .background(Color.black)
}
