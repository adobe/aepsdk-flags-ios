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

/// Manages polling and refresh of cached feature payloads for a single client.
final class SDKCacheManager {

    let clientCache: SDKClientCache
    private let policyCache: PolicyCache

    private let workQueue = DispatchQueue(label: "com.adobe.marketing.flags.cachemanager")
    private var apiProxy: APIProxy!
    private var clientId: String = ""

    private struct ResponseHeaders {
        var pollIntervalSeconds: Int
    }

    private var responseHeaders: ResponseHeaders?
    private var initialized = false
    private var paused = false
    private var pollGeneration: Int = 0

    private let metricsLock = NSLock()
    private var startPollingInvocationCount: Int = 0

    /// Invoked when embedded context metadata changes (`contextVersion` differs from cache).
    var onMetadataUpdated: ((MetadataResponse) -> Void)?

    init(policyCache: PolicyCache) {
        self.policyCache = policyCache
        self.clientCache = SDKClientCache()
    }

    /// Wire the manager to a client and perform the initial fetch + start polling.
    func configure(clientId: String, apiProxy: APIProxy) throws {
        self.clientId = clientId
        self.apiProxy = apiProxy

        workQueue.sync {
            Thread.current.name = "Flags-CacheManager-\(clientId)"
        }

        do {
            try initializeClient()
            startPolling()
            workQueue.sync { self.initialized = true }
            FlagLog.debug("[CacheManager] Initialized for client: \(clientId)")
        } catch {
            shutdown()
            throw FlagInitError.initializationFailed(message: "Failed to initialize cache manager", underlying: error)
        }
    }

    func refreshClientCache() {
        workQueue.async { [weak self] in
            self?.runCacheUpdateTask()
        }
    }

    /// Handles app state transitions — `nil` is a no-op (including after init).
    func onAppStateChanged(_ state: AppState?) {
        workQueue.async { [weak self] in
            guard let self = self, self.initialized else { return }
            guard let state = state else { return }
            if state == .background {
                if !self.paused {
                    self.paused = true
                    self.pollGeneration &+= 1
                }
            } else if state == .foreground {
                if self.paused {
                    self.paused = false
                    self.runForegroundResumeTask()
                }
            }
        }
    }

    func shutdown() {
        workQueue.sync {
            self.pollGeneration &+= 1
            self.initialized = false
            self.paused = false
        }
        clientCache.clear()
        policyCache.clear()
        workQueue.sync { self.responseHeaders = nil }
        FlagLog.debug("[CacheManager] Shutdown complete")
    }

    // MARK: - Initialization

    private func initializeClient() throws {
        guard !clientId.isEmpty else {
            throw FlagClientError.invalidArgument(message: "Client ID cannot be null or empty")
        }
        if !retryWithBackoff(maxRetries: FlagConstants.Cache.DEFAULT_MAX_RETRY_ATTEMPTS) {
            throw FlagClientError.operationFailed(message: "Failed to initialize client: \(clientId)", underlying: nil)
        }
        FlagLog.debug("[CacheManager] Client \(clientId) initialized")
    }

    private func retryWithBackoff(maxRetries: Int) -> Bool {
        var attempt = 0
        var delayMs = FlagConstants.Cache.DEFAULT_RETRY_DELAY_MS

        while attempt < maxRetries {
            do {
                try updateClientCache()
                return true
            } catch {
                FlagLog.warning("[CacheManager] Attempt \(attempt + 1) failed for client \(clientId): \(error.localizedDescription)")
            }
            attempt += 1
            if attempt < maxRetries {
                Thread.sleep(forTimeInterval: TimeInterval(delayMs) / 1000.0)
                delayMs = min(delayMs * 2, FlagConstants.Cache.MAX_RETRY_DELAY_MS)
            }
        }
        FlagLog.error("[CacheManager] All \(maxRetries) retries failed for client \(clientId)")
        return false
    }

    private func updateClientCache() throws {
        var contextVersion: String?
        if let metadataEntry = clientCache.getMetadata() {
            contextVersion = metadataEntry.contextVersion
        }

        let etag = clientCache.getFeaturesEtag(clientId: clientId)
        let response = try apiProxy.getFeatures(clientId: clientId,
                                                contextVersion: contextVersion,
                                                etag: etag)

        if !response.isChanged {
            return
        }

        let serverInterval = response.pollInterval
        let interval = serverInterval ?? getDefaultPollIntervalSeconds()
        responseHeaders = ResponseHeaders(pollIntervalSeconds: interval)

        if let featureGroups = response.featuresResponses {
            clientCache.putFeatures(clientId: clientId, features: featureGroups, etag: response.etag)
            cachePolicies(featureGroups: featureGroups)
        }

        updateMetadataCacheIfNeeded(from: response)
    }

    /// Metadata updates are gated solely by `contextVersion` — independent of feature groups.
    private func updateMetadataCacheIfNeeded(from response: FlagApiResponse) {
        guard let fgx = response.fgxResponse else { return }
        guard let contextVersion = fgx.contextVersion, !contextVersion.isEmpty else { return }

        let metadata = fgx.metadataResponse(etag: response.etag, isChanged: true)
        if clientCache.putMetadata(metadata) {
            onMetadataUpdated?(metadata)
        }
    }

    private func cachePolicies(featureGroups: [FeaturesResponse]) {
        for featureGroup in featureGroups {
            if let policyId = featureGroup.policyId, let detail = featureGroup.policy {
                policyCache.put(detail, for: policyId)
            }
            if let features = featureGroup.featuresObj {
                for feature in features {
                    if let policyId = feature.policyId, let detail = feature.policy {
                        policyCache.put(detail, for: policyId)
                    }
                }
            }
        }
    }

    // MARK: - Polling

    private func getDefaultPollIntervalSeconds() -> Int {
        return FlagConstants.Cache.DEFAULT_POLL_INTERVAL_SECONDS
    }

    private func startPolling() {
        metricsLock.lock()
        startPollingInvocationCount += 1
        metricsLock.unlock()

        pollGeneration &+= 1
        let generation = pollGeneration
        let intervalSeconds = TimeInterval(responseHeaders?.pollIntervalSeconds ?? getDefaultPollIntervalSeconds())
        schedulePoll(generation: generation, delay: intervalSeconds, interval: intervalSeconds)
        FlagLog.debug("[CacheManager] Polling started with interval \(intervalSeconds) seconds")
    }

    private func schedulePoll(generation: Int, delay: TimeInterval, interval: TimeInterval) {
        workQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard generation == self.pollGeneration, !self.paused else { return }

            let oldInterval = self.responseHeaders?.pollIntervalSeconds
            self.runCacheUpdateTask()
            let newInterval = self.responseHeaders?.pollIntervalSeconds

            if let newInterval = newInterval, newInterval != oldInterval, !self.paused {
                self.startPolling()
                return
            }

            self.schedulePoll(generation: generation, delay: interval, interval: interval)
        }
    }

    private func runCacheUpdateTask() {
        do {
            try updateClientCache()
        } catch {
            FlagLog.error("[CacheManager] Polling failed for client: \(clientId) — \(error)")
        }
    }

    private func runForegroundResumeTask() {
        do {
            try updateClientCache()
        } catch {
            FlagLog.error("[CacheManager] Foreground refresh failed for client: \(clientId) — \(error)")
        }
        startPolling()
    }

    // MARK: - Test hooks

    /// Blocks until all previously queued `workQueue` tasks finish (including `onAppStateChanged` handlers).
    internal func testDrainWorkQueue() {
        workQueue.sync { }
    }

    internal var testResponsePollIntervalSeconds: Int? {
        workQueue.sync { responseHeaders?.pollIntervalSeconds }
    }

    internal var testIsInitialized: Bool {
        workQueue.sync { initialized }
    }

    internal var testIsPaused: Bool {
        workQueue.sync { paused }
    }

    /// Number of times ``startPolling()`` ran (initial configure + each foreground resume).
    internal var testStartPollingInvocationCount: Int {
        metricsLock.lock()
        let v = startPollingInvocationCount
        metricsLock.unlock()
        return v
    }

    /// Poll generation increments when background cancels in-flight scheduled polls
    internal var testPollGeneration: Int {
        workQueue.sync { pollGeneration }
    }

    /// Runs one cache update synchronously
    internal func testRunScheduledPoll() {
        workQueue.sync {
            runCacheUpdateTask()
        }
    }
}
