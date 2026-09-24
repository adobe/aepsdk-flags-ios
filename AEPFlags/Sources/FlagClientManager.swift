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

import AEPCore
@_implementationOnly import FlagsEngine
import AEPServices
import Foundation

final class FlagClientManager {
    private static let selfTag = "FlagClientManager"

    /// Schedules the slow `FlagsMobileClientFactory.create()` call off the caller's thread.
    /// Abstracted (rather than a hardcoded `DispatchQueue`) so tests that need to hold this
    /// work "in flight" for a controlled window don't have to block a real thread out of
    /// GCD's shared, size-limited `.utility` worker pool -- see `DispatchQueue` conformance
    /// below for the production behavior this defaults to.
    protocol InitScheduler {
        func schedule(_ work: @escaping () -> Void)
    }

    private let extensionRuntime: ExtensionRuntime
    private let identityFetcher: FlagIdentityFetcher
    private let exposureQueue: FeatureExposureQueue

    private var featureClientInitialized = false
    private var initializationInProgress = false
    private var featureClient: FlagsMobileClientProtocol?

    /// Serializes all reads/writes of client state. `initScheduler` is used only for the slow
    /// `FlagsMobileClientFactory.create()` call; state mutations always land back here so
    /// extension-queue callers (`readyForEvent`, handlers) never race with background init.
    private let stateQueue = DispatchQueue(label: "com.adobe.flags.clientState")
    private let initScheduler: InitScheduler

    init(
        extensionRuntime: ExtensionRuntime,
        identityFetcher: FlagIdentityFetcher,
        exposureQueue: FeatureExposureQueue? = nil,
        initScheduler: InitScheduler? = nil
    ) {
        self.extensionRuntime = extensionRuntime
        self.identityFetcher = identityFetcher
        self.exposureQueue = exposureQueue ?? FeatureExposureQueue { events in
            FlagEdgeHandler.dispatchExposureEvents(extensionRuntime: extensionRuntime, events: events)
        }
        self.initScheduler = initScheduler ?? DispatchQueue(label: "com.adobe.flags.clientInit", qos: .utility)
    }

    func isClientReady() -> Bool {
        stateQueue.sync {
            isClientReadyLocked()
        }
    }

    func isInitializationInProgress() -> Bool {
        stateQueue.sync {
            initializationInProgress
        }
    }

    /// Starts asynchronous initialization of the Flags Mobile client.
    func startAsyncInitialization(configData: [String: Any], resolver: @escaping SharedStateResolver) {
        let startDecision: StartDecision = stateQueue.sync {
            if initializationInProgress || isClientReadyLocked() {
                return .skip
            }

            guard let config = FlagConfigurationProvider.buildConfiguration(configData) else {
                return .failConfiguration
            }

            initializationInProgress = true
            return .start(config)
        }

        switch startDecision {
        case .skip:
            return
        case .failConfiguration:
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - startAsyncInitialization - Failed to build SDK configuration."
            )
            resolver([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusFailed])
        case let .start(config):
            initScheduler.schedule { [weak self] in
                guard let self else {
                    resolver([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusFailed])
                    return
                }

                self.identityFetcher.warmUp()

                let createResult: Result<FlagsMobileClientProtocol, Error>
                do {
                    createResult = .success(try FlagsMobileClientFactory.create(configuration: config))
                } catch {
                    createResult = .failure(error)
                }

                self.stateQueue.async {
                    self.finishInitialization(createResult: createResult, resolver: resolver)
                }
            }
        }
    }

    func closeClient() {
        exposureQueue.shutdown()
        if !exposureQueue.awaitShutdown(timeout: 5.0) {
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - closeClient - Exposure queue did not terminate in time."
            )
        }

        stateQueue.sync {
            featureClient?.close()
            featureClient = nil
            featureClientInitialized = false
            initializationInProgress = false
        }
    }

    func processRequestEvent(_ event: Event) {
        guard let eventData = event.data else {
            return
        }

        let requestType = FlagDataReader.optString(eventData, key: FlagConstants.EventDataKeys.requestType, defaultValue: "") ?? ""

        switch requestType {
        case FlagConstants.EventDataValues.requestTypeGetFeature:
            handleGetFeature(event)
        case FlagConstants.EventDataValues.requestTypeIsEnabled:
            handleIsFeatureEnabled(event)
        default:
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - processRequestEvent - Unknown request type: \(requestType)"
            )
        }
    }

    func handleAppStateChange(_ appState: FlagsSDKAppState) {
        if appState == .background {
            exposureQueue.pausePeriodicFlush()
            exposureQueue.flush()
        } else if appState == .foreground {
            exposureQueue.resumePeriodicFlush()
        }

        let client = stateQueue.sync { () -> FlagsMobileClientProtocol? in
            guard isClientReadyLocked(), let client = featureClient else {
                return nil
            }
            return client
        }

        guard let client else {
            return
        }

        do {
            try client.setAppState(appState)
        } catch let error as FlagClientError {
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - handleAppStateChange - Failed: \(error.localizedDescription)"
            )
        } catch {
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - handleAppStateChange - Failed: \(error.localizedDescription)"
            )
        }
    }

    func dispatchErrorResponse(_ event: Event, error: AEPError) {
        dispatchErrorResponseInternal(event, error: error)
    }

    // MARK: - Testing

    func setFeatureClient(_ client: FlagsMobileClientProtocol?) {
        stateQueue.sync {
            featureClient = client
        }
    }

    func setFeatureClientInitialized(_ initialized: Bool) {
        stateQueue.sync {
            featureClientInitialized = initialized
        }
    }

    func isFeatureClientInitialized() -> Bool {
        stateQueue.sync {
            featureClientInitialized
        }
    }

    // MARK: - Private

    private enum StartDecision {
        case skip
        case failConfiguration
        case start(FlagsSDKConfiguration)
    }

    private func isClientReadyLocked() -> Bool {
        guard let client = featureClient else {
            return false
        }
        return featureClientInitialized && client.isClientInitialized
    }

    private func guardClientIdOrError(client: FlagsMobileClientProtocol, event: Event, handler: String) -> Bool {
        let clientId = client.mobileClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty else {
            Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - \(handler) - Client ID is missing.")
            dispatchErrorResponseInternal(event, error: .unexpected)
            return false
        }
        return true
    }

    private func finishInitialization(createResult: Result<FlagsMobileClientProtocol, Error>, resolver: @escaping SharedStateResolver) {
        defer { initializationInProgress = false }

        switch createResult {
        case let .success(client):
            featureClient = client
            featureClientInitialized = true
            Log.debug(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - Feature SDK client initialized successfully."
            )
            resolver([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        case let .failure(error as FlagInitError):
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - Feature SDK client initialization failed: \(error.localizedDescription)"
            )
            resolver([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusFailed])
        case let .failure(error):
            Log.warning(
                label: FlagConstants.logTag,
                "\(Self.selfTag) - Feature SDK client initialization unexpected error: \(error.localizedDescription)"
            )
            resolver([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusFailed])
        }
    }

    private func handleGetFeature(_ event: Event) {
        do {
            guard let eventData = event.data else {
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            guard let featureName = FlagDataReader.optString(eventData, key: FlagConstants.EventDataKeys.featureName),
                  !featureName.isEmpty else {
                Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleGetFeature - Feature name is missing.")
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            let client = stateQueue.sync { featureClient }
            guard let client else {
                Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleGetFeature - Feature SDK client instance is null.")
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            guard guardClientIdOrError(client: client, event: event, handler: "handleGetFeature") else {
                return
            }

            let context = eventData[FlagConstants.EventDataKeys.context] as? [String: [String]]
            let identityMap = identityFetcher.fetchIdentityMap(extensionRuntime: extensionRuntime, event: event)
            let request = GetFeatureRequestFactory.create(context: context, identityMap: identityMap)

            let feature = try client.getFeature(named: featureName, request: request)

            var responseData: [String: Any] = [:]
            if let feature {
                responseData[FlagConstants.EventDataKeys.feature] = FeatureResultMapper.featureResultToMap(feature)
            }

            let responseEvent = event.createResponseEvent(
                name: FlagConstants.EventNames.flagsResponse,
                type: FlagConstants.EventType.flags,
                source: FlagConstants.EventSource.responseContent,
                data: responseData
            )

            extensionRuntime.dispatch(event: responseEvent)

            queueExposureEvent(feature)
        } catch let error as FlagClientError {
            Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleGetFeature - Failed: \(error.localizedDescription)")
            dispatchErrorResponseInternal(event, error: .unexpected)
        } catch {
            Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleGetFeature - Unexpected error: \(error.localizedDescription)")
            dispatchErrorResponseInternal(event, error: .unexpected)
        }
    }

    private func handleIsFeatureEnabled(_ event: Event) {
        do {
            guard let eventData = event.data else {
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            guard let featureName = FlagDataReader.optString(eventData, key: FlagConstants.EventDataKeys.featureName),
                  !featureName.isEmpty else {
                Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleIsFeatureEnabled - Feature name is missing.")
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            let client = stateQueue.sync { featureClient }
            guard let client else {
                Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleIsFeatureEnabled - Feature SDK client instance is null.")
                dispatchErrorResponseInternal(event, error: .unexpected)
                return
            }

            guard guardClientIdOrError(client: client, event: event, handler: "handleIsFeatureEnabled") else {
                return
            }

            let context = eventData[FlagConstants.EventDataKeys.context] as? [String: [String]]
            let identityMap = identityFetcher.fetchIdentityMap(extensionRuntime: extensionRuntime, event: event)
            let request = GetFeatureRequestFactory.create(context: context, identityMap: identityMap)

            let feature = try client.getFeature(named: featureName, request: request)
            let isEnabled = FeatureResultMapper.isEnabledFeatureResult(feature)

            let responseData: [String: Any] = [
                FlagConstants.EventDataKeys.isEnabled: isEnabled
            ]

            let responseEvent = event.createResponseEvent(
                name: FlagConstants.EventNames.flagsResponse,
                type: FlagConstants.EventType.flags,
                source: FlagConstants.EventSource.responseContent,
                data: responseData
            )

            extensionRuntime.dispatch(event: responseEvent)

            queueExposureEvent(feature)
        } catch let error as FlagClientError {
            Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleIsFeatureEnabled - Failed: \(error.localizedDescription)")
            dispatchErrorResponseInternal(event, error: .unexpected)
        } catch {
            Log.warning(label: FlagConstants.logTag, "\(Self.selfTag) - handleIsFeatureEnabled - Unexpected error: \(error.localizedDescription)")
            dispatchErrorResponseInternal(event, error: .unexpected)
        }
    }

    private func queueExposureEvent(_ feature: FlagsSDKFeatureResult?) {
        guard ExposureEventIdGenerator.isExposureEligible(feature),
              let feature,
              let aggregationKey = ExposureEventIdGenerator.generateAggregationKey(feature),
              !aggregationKey.isEmpty else {
            return
        }

        let evaluatedAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        exposureQueue.enqueue(
            aggregationKey: aggregationKey,
            feature: feature,
            evaluatedAtMillis: evaluatedAtMillis
        )
    }

    private func dispatchErrorResponseInternal(_ event: Event, error: AEPError) {
        let responseData: [String: Any] = [
            FlagConstants.EventDataKeys.responseError: error.rawValue
        ]

        let responseEvent = event.createResponseEvent(
            name: FlagConstants.EventNames.flagsResponse,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.responseContent,
            data: responseData
        )

        extensionRuntime.dispatch(event: responseEvent)
    }
}

extension DispatchQueue: FlagClientManager.InitScheduler {
    func schedule(_ work: @escaping () -> Void) {
        self.async(execute: work)
    }
}
