//
//  TicTacToeiOS.swift
//  tic_tac_toe_ios_ethereum
//
//  Created by Agent Malone on 5/13/25.
//

import SwiftUI

@main // Tells Swift this is where the app starts
struct TicTacToeiOSApp: App { // Make sure struct name matches your project name + "App"
    
    init() {
        // You can put one-time setup code here if needed when the app first launches
        print("TicTacToeiOSApp is starting up!")
    }

    var body: some Scene {
        WindowGroup { // The main window of the app
            ContentView() // Show our main screen (ContentView) inside the window
        }
    }
}
