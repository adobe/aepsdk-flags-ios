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

/// Flags Mobile SDK client for feature evaluation. Thread-safe. Exposed to Objective-C as `AEPMobileFlagEngine`.
@objc(AEPMobileFlagEngine)
public final class Flag: NSObject {

    let configuration: FlagConfiguration
    @objc public let clientId: String

    let apiProxy: APIProxy
    let cacheManager: SDKCacheManager
    let cache: SDKClientCache
    let evaluator: FeatureEvaluator

    let stateQueue = DispatchQueue(label: "com.adobe.marketing.flags.state")
    var _initialized: Bool = false
    var _closed: Bool = false

    init(configuration: FlagConfiguration) {
        self.configuration = configuration
        self.clientId = configuration.clientId

        self.apiProxy = APIProxy(
            edgeBaseUrl: FeatureServiceUrls.baseUrl(fromEdgeDomain: configuration.edgeDomain),
            imsOrg: configuration.imsOrg,
            sandboxName: configuration.sandboxName,
            sharedSession: configuration.urlSession,
            sdkVersion: configuration.sdkVersion)

        let policyCache = PolicyCache()
        self.cacheManager = SDKCacheManager(policyCache: policyCache)
        self.cache = cacheManager.clientCache
        self.evaluator = FeatureEvaluator(clientId: clientId, cache: cache, policyCache: policyCache)

        super.init()
    }

    func initialize() throws {
        cacheManager.onMetadataUpdated = { [weak self] metadata in
            self?.evaluator.setFilterService(FilterService(fieldDataTypeCache: metadata.fieldDataTypeCache))
        }

        try cacheManager.configure(clientId: clientId, apiProxy: apiProxy)

        stateQueue.sync { _initialized = true }
        FlagLog.debug("[Flags] SDK initialized successfully")
    }

    func ensureInitialized() throws {
        let isReady = stateQueue.sync { _initialized && !_closed }
        if !isReady {
            throw FlagClientError.notInitialized
        }
    }

    func shutdown() {
        evaluator.clearFilterService()
        cacheManager.shutdown()
        apiProxy.shutdown()
        FlagLog.debug("[Flags] SDK shutdown complete")
    }

    // MARK: - Test hooks

    /// Marks the client initialized without network I/O.
    internal func testMarkInitializedWithoutNetwork() {
        stateQueue.sync {
            _initialized = true
            _closed = false
        }
    }

    internal func testMarkUninitialized() {
        stateQueue.sync { _initialized = false }
    }

    /// Seed `SDKClientCache` for unit tests.
    internal var testClientCacheForUnitTests: SDKClientCache { cache }
}
