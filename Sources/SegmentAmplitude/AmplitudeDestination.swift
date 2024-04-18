//
//  File.swift
//  
//
//  Created by Brandon Sneed on 4/16/24.
//

import Foundation
import AmplitudeSwift
import Segment

public class AmplitudeDestination: DestinationPlugin {
    public let key = "Actions Amplitude"
    public let type = Segment.PluginType.destination
    public let timeline = Timeline()
    public var analytics: Analytics? = nil
    
}
