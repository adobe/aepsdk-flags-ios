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

import Foundation

// MARK: - Swift-idiomatic surface (throws)

public extension Flag {

    /// Returns all evaluated features.
    func getFeatures(for request: GetFeatureRequest?) throws -> [FeatureResult] {
        try ensureInitialized()
        let req = request ?? GetFeatureRequest.defaultRequest
        return evaluator.evaluateAll(request: req)
    }

    /// Returns evaluation result for a single feature, or `nil` if not found.
    func getFeature(named featureName: String,
                    for request: GetFeatureRequest?) throws -> FeatureResult? {
        try ensureInitialized()
        let req = request ?? GetFeatureRequest.defaultRequest
        return evaluator.evaluate(featureName: featureName, request: req)
    }

    /// Returns whether the named feature is enabled.
    func isFeatureEnabled(_ featureName: String,
                          for request: GetFeatureRequest?) throws -> Bool {
        try ensureInitialized()
        let req = request ?? GetFeatureRequest.defaultRequest
        return evaluator.isEnabled(featureName: featureName, request: req)
    }

    /// Refresh the feature cache.
    func refreshCache() throws {
        try ensureInitialized()
        cacheManager.refreshClientCache()
    }

    /// Notify the SDK of the host application's lifecycle state.
    func setAppState(_ state: AppState) throws {
        try ensureInitialized()
        cacheManager.onAppStateChanged(state)
        if state == .background {
            apiProxy.evictIdleConnections()
        }
    }
}

// MARK: - Objective-C bridging surface
//
// `@objc` + `throws` cannot return raw `Bool` or an optional reference type
// because Obj-C uses `nil` / `NO` to signal a thrown error. We expose Obj-C
// callers an explicit `NSError **` out-parameter variant instead.

@objc public extension Flag {

    @objc(getFeaturesForRequest:error:)
    func _objc_getFeatures(for request: GetFeatureRequest?) throws -> [FeatureResult] {
        return try getFeatures(for: request)
    }

    @objc(getFeatureNamed:request:error:)
    func _objc_getFeature(named featureName: String,
                          for request: GetFeatureRequest?,
                          error: NSErrorPointer) -> FeatureResult? {
        do {
            return try getFeature(named: featureName, for: request)
        } catch let thrown {
            error?.pointee = thrown as NSError
            return nil
        }
    }

    @objc(isFeatureEnabledNamed:request:error:)
    func _objc_isFeatureEnabled(_ featureName: String,
                                for request: GetFeatureRequest?,
                                error: NSErrorPointer) -> Bool {
        do {
            return try isFeatureEnabled(featureName, for: request)
        } catch let thrown {
            error?.pointee = thrown as NSError
            return false
        }
    }

    @objc(refreshCacheAndReturnError:)
    func _objc_refreshCache() throws {
        try refreshCache()
    }

    @objc(setAppState:error:)
    func _objc_setAppState(_ state: AppState) throws {
        try setAppState(state)
    }

    /// The configuration this client was created with.
    var sdkConfiguration: FlagConfiguration {
        return configuration
    }
}
