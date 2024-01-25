//
//  BasicExampleApp.swift
//  BasicExample
//
//  Created by Brandon Sneed on 2/23/22.
//

import SwiftUI
import Segment
import SegmentAmplitude

@main
struct BasicExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

var instance: Analytics? = nil

extension Analytics {
    static var main: Analytics {
        if instance == nil {
            instance = Analytics(configuration: Configuration(writeKey: "<WRITE_KEY>")
                        .flushAt(3)
                        .trackApplicationLifecycleEvents(true))
            instance?.add(plugin: AmplitudeSession())
        }
        
        return instance!
    }
}
