//
//  AmplitudeSession.swift
//
//  Created by Cody Garvin on 2/16/21.
//

// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import UIKit

@objc(SEGAmplitudeSession)
public class ObjCAmplitudeSession: NSObject, ObjCPlugin, ObjCPluginShim {
    public func instance() -> EventPlugin { return AmplitudeSession() }
}

public class AmplitudeSession: EventPlugin, iOSLifecycle {
    public var key = "Actions Amplitude"
    public var type = PluginType.enrichment
    public weak var analytics: Analytics?
    
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
    }
    
    @Atomic private var active = false
    @Atomic private var inForeground: Bool = false
    private var storage = Storage()
    
    @Atomic var sessionID: Int64 {
        didSet {
            storage.write(key: Storage.Constants.previousSessionID, value: sessionID)
            print("sessionID = \(sessionID)")
        }
    }
    
    @Atomic var lastEventTime: Int64 {
        didSet {
            storage.write(key: Storage.Constants.lastEventTime, value: lastEventTime)
        }
    }
    
    public init() {
        self.sessionID = storage.read(key: Storage.Constants.previousSessionID) ?? -1
        self.lastEventTime = storage.read(key: Storage.Constants.lastEventTime) ?? -1
    }
    
    public func update(settings: Settings, type: UpdateType) {
        if type != .initial { return }
            
        if settings.hasIntegrationSettings(key: key) {
            active = true
        } else {
            active = false
        }
        
        if sessionID == -1 {
            startNewSession()
        } else {
            startNewSessionIfNecessary()
        }
    }
    
    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event else { return nil }
        guard let event = defaultEventHandler(event: event) else { return nil }
        
        if var trackEvent = event as? TrackEvent {
            let eventName = trackEvent.event
            
            if eventName.contains(Constants.ampPrefix)
                || eventName == Constants.ampSessionStartEvent
                || eventName == Constants.ampSessionEndEvent {
                trackEvent.integrations = try? JSON([
                    "all": false,
                    "\(key)": ["session_id": sessionID]
                ])
            }
            
            // handle events that need to be re-generated back to amplitude.
            // block the originals from going to amplitude as well.
            switch trackEvent.event {
            case "Application Opened":
                analytics?.track(name: Constants.ampAppOpenedEvent, properties: trackEvent.properties)
                trackEvent.integrations?.setValue(false, forKeyPath: KeyPath(key))
            case "Application Installed":
                analytics?.track(name: Constants.ampAppInstalledEvent, properties: trackEvent.properties)
                trackEvent.integrations?.setValue(false, forKeyPath: KeyPath(key))
            case "Application Updated":
                analytics?.track(name: Constants.ampAppUpdatedEvent, properties: trackEvent.properties)
                trackEvent.integrations?.setValue(false, forKeyPath: KeyPath(key))
            case "Application Backgrounded":
                analytics?.track(name: Constants.ampAppBackgroundedEvent, properties: trackEvent.properties)
                trackEvent.integrations?.setValue(false, forKeyPath: KeyPath(key))
            case "Application Foregrounded":
                // amplitude doesn't need this one, it's redundant.
                trackEvent.integrations?.setValue(false, forKeyPath: KeyPath(key))
            default:
                break
            }
            
            return trackEvent as? T
        }
        
        lastEventTime = newTimestamp()
        return event
    }
    
    public func reset() {
        resetSession()
    }
    
    public func applicationWillEnterForeground(application: UIApplication?) {
        startNewSessionIfNecessary()
        print("Foreground: \(sessionID)")
        analytics?.log(message: "Amplitude Session ID: \(sessionID)")
    }
    
    public func applicationWillResignActive(application: UIApplication?) {
        print("Background: \(sessionID)")
        lastEventTime = newTimestamp()
    }
}

extension AmplitudeSession: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}


// MARK: - AmplitudeSession Helper Methods

extension AmplitudeSession {
    private func defaultEventHandler<T: RawEvent>(event: T) -> T? {
        guard let returnEvent = insertSession(event: event) as? T else {
            return nil
        }
        return returnEvent
    }
    
    private func resetSession() {
        if sessionID != -1 {
            endSession()
        }
        startNewSession()
    }
    
    private func startNewSession() {
        sessionID = newTimestamp()
        analytics?.track(name: Constants.ampSessionStartEvent)
    }
    
    private func startNewSessionIfNecessary() {
        let timestamp = newTimestamp()
        let withinSessionLimit = withinMinSessionTime(timestamp: timestamp)
        if sessionID >= 0 && withinSessionLimit {
            return
        }
        // end previous session
        analytics?.track(name: Constants.ampSessionEndEvent)
        // start new session
        startNewSession()
        analytics?.track(name: Constants.ampSessionStartEvent)
    }
    
    private func endSession() {
        analytics?.track(name: Constants.ampSessionEndEvent)
    }
    
    private func insertSession(event: RawEvent) -> RawEvent {
        var returnEvent = event
        if var integrations = event.integrations?.dictionaryValue {
            integrations[key] = ["session_id": sessionID]
            returnEvent.integrations = try? JSON(integrations as Any)
        }
        return returnEvent
    }
    
    private func newTimestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    private func withinMinSessionTime(timestamp: Int64) -> Bool {
        let minMilisecondsBetweenSessions = 300_000
        let timeDelta = timestamp - self.lastEventTime
        return timeDelta < minMilisecondsBetweenSessions
    }
}

// MARK: - Storage for Session information

extension AmplitudeSession {
    internal class Storage {
        internal struct Constants {
            static let lastEventID = "last_event_id"
            static let previousSessionID = "previous_session_id"
            static let lastEventTime = "last_event_time"
        }
        
        private var userDefaults = UserDefaults(suiteName: "com.segment.amplitude.session")
        private func isBasicType<T: Codable>(value: T?) -> Bool {
            var result = false
            if value == nil {
                result = true
            } else {
                switch value {
                // NSNull is not valid for UserDefaults
                //case is NSNull:
                //    fallthrough
                case is Decimal:
                    fallthrough
                case is NSNumber:
                    fallthrough
                case is Bool:
                    fallthrough
                case is String:
                    result = true
                default:
                    break
                }
            }
            return result
        }
        
        func read<T: Codable>(key: String) -> T? {
            return userDefaults?.value(forKey: key) as? T
        }
        
        func write<T: Codable>(key: String, value: T?) {
            if let value, isBasicType(value: value) {
                userDefaults?.setValue(value, forKey: key)
            }
        }
    }
}
