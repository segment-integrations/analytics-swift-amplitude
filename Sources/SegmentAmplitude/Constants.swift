//
//  Constants.swift
//  
//
//  Created by Brandon Sneed on 7/9/24.
//

import Foundation

internal struct Constants {
    static let ampPrefix = "[Amplitude] "
    
    static let ampSessionEndEvent = "session_end"
    static let ampSessionStartEvent = "session_start"
    static let ampAppInstalledEvent = "\(ampPrefix)Application Installed"
    static let ampAppUpdatedEvent = "\(ampPrefix)Application Updated"
    static let ampAppOpenedEvent = "\(ampPrefix)Application Opened"
    static let ampAppBackgroundedEvent = "\(ampPrefix)Application Backgrounded"
    static let ampDeepLinkOpenedEvent = "\(ampPrefix)Deep Link Opened"
    static let ampScreenViewedEvent = "\(ampPrefix)Screen Viewed"
    static let ampScreenNameProperty = "\(ampPrefix)Screen Name"
}
