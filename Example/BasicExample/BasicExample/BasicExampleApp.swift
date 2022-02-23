//
//  BasicExampleApp.swift
//  BasicExample
//
//  Created by Brandon Sneed on 2/23/22.
//

import SwiftUI
import Segment

@main
struct BasicExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

extension Analytics {
    static var main: Analytics {
        let analytics = Analytics(configuration: Configuration(writeKey: "<YOUR WRITE KEY>")
                    .flushAt(3)
                    .trackApplicationLifecycleEvents(true))
        //analytics.add(plugin: <Destination>())
        return analytics
    }
}
