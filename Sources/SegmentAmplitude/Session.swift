//
//  SessionTracker.swift
//
//
//  Created by Brandon Sneed on 4/22/24.
//

import Foundation
import Segment

// MARK: - Amplitude Session Management

internal class Session {
    @Atomic var sessionID: Int64 {
        didSet {
            storage.write(key: Storage.Constants.previousSessionID, value: sessionID)
        }
    }
    
    @Atomic var lastEventTime: Int64 {
        didSet {
            storage.write(key: Storage.Constants.lastEventTime, value: lastEventTime)
        }
    }
    
    private var inForeground: Bool = true
    private var storage = Storage()
    
    init() {
        self.sessionID = storage.read(key: Storage.Constants.previousSessionID) ?? -1
        self.lastEventTime = storage.read(key: Storage.Constants.lastEventTime) ?? -1
    }
    
    
    
    func startNewSession(analytics: Analytics) {
        let timestamp = newTimestamp()
        if sessionID >= 0 && (inForeground || withinMinSessionTime(timestamp: timestamp)) {
            return
        }
        // end previous session
        analytics.track(name: Constants.ampSessionEndEvent)
        // start new session
        sessionID = timestamp
        analytics.track(name: Constants.ampSessionStartEvent)
    }
}

// MARK: - Session helper functions

extension Session {
    private func newTimestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    private func withinMinSessionTime(timestamp: Int64) -> Bool {
        let minMilisecondsBetweenSessions = 300_000
        let timeDelta = timestamp - self.lastEventTime
        return timeDelta < minMilisecondsBetweenSessions
    }
}

// MARK: - Session Storage

extension Session {
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
