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

@_implementationOnly import FlagsEngine
import Foundation

// Type aliases for Flags engine types used by the extension.
typealias FlagsSDKConfiguration = FlagConfiguration
typealias FlagsSDKGetFeatureRequest = GetFeatureRequest
typealias FlagsSDKFeatureResult = FeatureResult
typealias FlagsSDKAppState = AppState

/// Abstraction over the Flags Mobile SDK (`FlagsEngine.Flag`) for extension internals and unit tests.
protocol FlagsMobileClientProtocol: AnyObject {
    var isClientInitialized: Bool { get }
    var mobileClientId: String { get }
    func getFeature(named featureName: String, request: FlagsSDKGetFeatureRequest) throws -> FlagsSDKFeatureResult?
    func isFeatureEnabled(_ featureName: String, request: FlagsSDKGetFeatureRequest) throws -> Bool
    func setAppState(_ state: FlagsSDKAppState) throws
    func close()
}

/// Wraps `FlagsEngine.Flag` — the extension module also defines `Flag` (AEP Extension), so we cannot extend the mobile client type in-module.
final class FlagsMobileClientWrapper: FlagsMobileClientProtocol {
    private let client: FlagsEngine.Flag

    init(client: FlagsEngine.Flag) {
        self.client = client
    }

    var isClientInitialized: Bool {
        client.isInitialized
    }

    var mobileClientId: String {
        client.clientId
    }

    func getFeature(named featureName: String, request: FlagsSDKGetFeatureRequest) throws -> FlagsSDKFeatureResult? {
        try client.getFeature(named: featureName, for: request)
    }

    func isFeatureEnabled(_ featureName: String, request: FlagsSDKGetFeatureRequest) throws -> Bool {
        try client.isFeatureEnabled(featureName, for: request)
    }

    func setAppState(_ state: FlagsSDKAppState) throws {
        try client.setAppState(state)
    }

    func close() {
        client.close()
    }
}

enum FlagsMobileClientFactory {
    /// Test-only seam allowing unit tests to inject a mock client or simulate an initialization failure
    /// without contacting the real Flags Mobile SDK. When `nil` (production default), `create` builds the
    /// real `FlagsEngine.Flag`. Tests must reset this to `nil` in `tearDown`.
    static var createOverride: ((FlagsSDKConfiguration) throws -> FlagsMobileClientProtocol)?

    /// Creates and initializes a Flags Mobile SDK client (`Flag.create(configuration:)`).
    static func create(configuration: FlagsSDKConfiguration) throws -> FlagsMobileClientProtocol {
        if let createOverride {
            return try createOverride(configuration)
        }
        let client = try FlagsEngine.Flag.create(configuration: configuration)
        return FlagsMobileClientWrapper(client: client)
    }
}
