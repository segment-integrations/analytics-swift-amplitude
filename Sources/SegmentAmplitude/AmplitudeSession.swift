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
    
    public var logging: Bool = false
    
    @Atomic private var active = false
    @Atomic private var inForeground: Bool = false
    @Atomic private var resetPending: Bool = false
    private var storage = Storage()
    
    internal var eventSessionID: Int64 = -1
    @Atomic internal var sessionID: Int64 = -1 {
        didSet {
            storage.write(key: Storage.Constants.previousSessionID, value: sessionID)
            debugLog("sessionID set to: \(sessionID)")
        }
    }
    
    @Atomic internal var lastEventTime: Int64 = -1 {
        didSet {
            storage.write(key: Storage.Constants.lastEventTime, value: lastEventTime)
        }
    }
    
    public init() {
        _sessionID.set(storage.read(key: Storage.Constants.previousSessionID) ?? -1)
        _lastEventTime.set(storage.read(key: Storage.Constants.lastEventTime) ?? -1)
        
        debugLog("startup sessionID = \(sessionID)")
    }
    
    public func configure(analytics: Analytics) {
        self.analytics = analytics
        
        if sessionID == -1 {
            startNewSession()
        } else {
            startNewSessionIfNecessary()
        }
    }
    
    public func update(settings: Settings, type: UpdateType) {
        if type != .initial { return }
            
        if settings.hasIntegrationSettings(key: key) {
            _active.set(true)
        } else {
            _active.set(false)
        }
    }
    
    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event else { return nil }
        var workingEvent = defaultEventHandler(event: event)
        
        debugLog("execute called")
        
        // check if time has elapsed and kick of a new session if it has.
        // this will send events back through to do the tasks; nothing really happens inline.
        startNewSessionIfNecessary()
        
        // handle screen
        // this code works off the destination action logic.
        if var screenEvent = workingEvent as? ScreenEvent, let screenName = screenEvent.name {
            var adjustedProps = screenEvent.properties
            // amp needs the `name` in the properties
            if adjustedProps == nil {
                adjustedProps = try? JSON(["name": screenName])
            } else {
                adjustedProps?.setValue(screenName, forKeyPath: JSONKeyPath("name"))
            }
            screenEvent.properties = adjustedProps
            workingEvent = screenEvent as? T
        }

        
        // handle track
        if var trackEvent = workingEvent as? TrackEvent {
            let eventName = trackEvent.event
        
            // if it's a start event, set a new sessionID
            if eventName == Constants.ampSessionStartEvent {
                _resetPending.set(false)
                eventSessionID = sessionID
                debugLog("NewSession = \(eventSessionID)")
            }
            
            if eventName == Constants.ampSessionEndEvent {
                debugLog("EndSession = \(eventSessionID)")
            }
            
            // if it's amp specific stuff, disable all the integrations except for amp.
            if eventName.contains(Constants.ampPrefix) || eventName == Constants.ampSessionStartEvent || eventName == Constants.ampSessionEndEvent {
                var integrations = disableAllIntegrations(integrations: trackEvent.integrations)
                integrations?.setValue(["session_id": eventSessionID], forKeyPath: JSONKeyPath(key))
                trackEvent.integrations = integrations
            }
            
            workingEvent = trackEvent as? T
        }
        
        _lastEventTime.set(newTimestamp())
        return workingEvent
    }
    
    public func reset() {
        resetSession()
    }
    
    public func applicationWillEnterForeground(application: UIApplication?) {
        startNewSessionIfNecessary()
        debugLog("Foreground: \(eventSessionID)")
    }
    
    public func applicationWillResignActive(application: UIApplication?) {
        debugLog("Background: \(eventSessionID)")
        _lastEventTime.set(newTimestamp())
    }
}

extension AmplitudeSession: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
            
}
#if os(watchOS)
extension AmplitudeSession: watchOSLifecycle {
    public func applicationWillEnterForeground(watchExtension: WKExtension) {
            startNewSessionIfNecessary()
            debugLog("Foreground: \(eventSessionID)")
        }
    
    public func applicationWillResignActive(watchExtension: WKExtension) {
        debugLog("Background: \(eventSessionID)")
        _lastEventTime.set(newTimestamp())
        }
    }
#endif


// MARK: - AmplitudeSession Helper Methods

extension AmplitudeSession {
    private func disableAllIntegrations(integrations: JSON?) -> JSON? {
        var result = integrations
        if let keys = integrations?.dictionaryValue?.keys {
            for key in keys {
                result?.setValue(false, forKeyPath: JSONKeyPath(key))
            }
        }
        return result
    }
    
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
        if resetPending { return }
        _resetPending.set(true)
        _sessionID.set(newTimestamp())
        if eventSessionID == -1 {
            // we only wanna do this if we had nothing before, so each
            // event actually HAS a sessionID of some kind associated.
            eventSessionID = sessionID
        }
        analytics?.track(name: Constants.ampSessionStartEvent)
    }
    
    private func startNewSessionIfNecessary() {
        if eventSessionID == -1 {
            // we only wanna do this if we had nothing before, so each
            // event actually HAS a sessionID of some kind associated.
            eventSessionID = sessionID
        }
        
        if resetPending { return }
        let timestamp = newTimestamp()
        let withinSessionLimit = withinMinSessionTime(timestamp: timestamp)
        if sessionID >= 0 && withinSessionLimit {
            return
        }
        
        // we'll consider this our new lastEventTime
        _lastEventTime.set(timestamp)
        // end previous session
        endSession()
        // start new session
        startNewSession()
    }
    
    private func endSession() {
        analytics?.track(name: Constants.ampSessionEndEvent)
    }
    
    private func insertSession(event: RawEvent) -> RawEvent {
        var returnEvent = event
        if var integrations = event.integrations?.dictionaryValue {
            integrations[key] = ["session_id": eventSessionID]
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
    
    private func debugLog(_ str: String) {
        if logging {
            print("[AmplitudeSession] \(str)")
        }
        analytics?.log(message: "[AmplitudeSession] \(str)")
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
