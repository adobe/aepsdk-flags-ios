/*
 Copyright 2026 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

@testable import AEPFlags
import FlagsEngine
import Foundation

final class MockFlagsMobileClient: FlagsMobileClientProtocol {
    var isClientInitialized = true
    var mobileClientId = "test-client"
    var featureResult: FlagsSDKFeatureResult?
    var featureEnabled = false
    var getFeatureError: FlagClientError?
    var isFeatureEnabledError: FlagClientError?

    var lastAppState: FlagsSDKAppState? {
        lock.sync { _lastAppState }
    }

    var closed: Bool {
        lock.sync { _closed }
    }

    var lastGetFeatureRequest: FlagsSDKGetFeatureRequest? {
        lock.sync { _lastGetFeatureRequest }
    }

    var lastIsFeatureEnabledRequest: FlagsSDKGetFeatureRequest? {
        lock.sync { _lastIsFeatureEnabledRequest }
    }

    var isFeatureEnabledCallCount: Int {
        lock.sync { _isFeatureEnabledCallCount }
    }

    /// Guards the mutable state above. A single `FlagClientManager` (and therefore a single mock
    /// client instance) can be invoked from multiple threads concurrently in real usage — e.g. two
    /// simultaneous API calls both landing on the extension's serial queue at slightly different
    /// times — so this mock needs to be safe under concurrent access, not just single-threaded tests.
    private let lock = NSLock()
    private var _lastAppState: FlagsSDKAppState?
    private var _closed = false
    private var _lastGetFeatureRequest: FlagsSDKGetFeatureRequest?
    private var _lastIsFeatureEnabledRequest: FlagsSDKGetFeatureRequest?
    private var _isFeatureEnabledCallCount = 0

    func getFeature(named featureName: String, request: FlagsSDKGetFeatureRequest) throws -> FlagsSDKFeatureResult? {
        lock.sync { _lastGetFeatureRequest = request }
        _ = featureName
        if let getFeatureError {
            throw getFeatureError
        }
        return featureResult
    }

    func isFeatureEnabled(_ featureName: String, request: FlagsSDKGetFeatureRequest) throws -> Bool {
        lock.sync {
            _isFeatureEnabledCallCount += 1
            _lastIsFeatureEnabledRequest = request
        }
        _ = featureName
        if let isFeatureEnabledError {
            throw isFeatureEnabledError
        }
        return featureEnabled
    }

    func setAppState(_ state: FlagsSDKAppState) throws {
        lock.sync { _lastAppState = state }
    }

    func close() {
        lock.sync { _closed = true }
    }
}

private extension NSLock {
    func sync<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
