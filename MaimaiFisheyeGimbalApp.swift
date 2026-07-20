// MaimaiFisheyeGimbalApp.swift
import SwiftUI

@main
struct MaimaiFisheyeGimbalApp: App {
    init() {
        CrashCatcher.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBarHidden(true)
                .preferredColorScheme(.dark)
        }
    }
}
