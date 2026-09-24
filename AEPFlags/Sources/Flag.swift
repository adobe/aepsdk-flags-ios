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
import AEPServices
import Foundation

/// Exposed to Objective-C as `AEPMobileFlag`.
@objc(AEPMobileFlag)
public class Flag: NSObject, Extension {
    public static var extensionVersion: String = FlagConstants.extensionVersion
    public var name = FlagConstants.extensionName
    public var friendlyName = FlagConstants.friendlyName
    public var metadata: [String: String]?
    public var runtime: ExtensionRuntime

    private let clientManager: FlagClientManager
    private let identityFetcher: FlagIdentityFetcher

    private static let selfTag = "FlagExtension"

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        let fetcher = EdgeIdentityFetcher()
        identityFetcher = fetcher
        clientManager = FlagClientManager(extensionRuntime: runtime, identityFetcher: fetcher)
        super.init()
    }

    init(runtime: ExtensionRuntime, clientManager: FlagClientManager, identityFetcher: FlagIdentityFetcher) {
        self.runtime = runtime
        self.clientManager = clientManager
        self.identityFetcher = identityFetcher
        super.init()
    }

    public func onRegistered() {
        registerListener(
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            listener: handleFlagRequestContent
        )

        registerListener(
            type: EventType.configuration,
            source: EventSource.responseContent,
            listener: handleConfigurationResponse
        )

        registerListener(
            type: EventType.genericLifecycle,
            source: EventSource.requestContent,
            listener: handleLifecycleEvent
        )

        // Config peek (event: nil): if Configuration shared state is already available at registration
        // time, start client initialization here. This is one of only two init entry points (the other is
        // `handleConfigurationResponse`); it prevents a deadlock when a flag API event arrives before the
        // Configuration response event: start client initialization when config arrives after registration.
        if let configData = getConfigurationData(event: nil) {
            tryStartInitialization(event: nil, configData: configData)
        }
    }

    public func onUnregistered() {
        clientManager.closeClient()
    }

    /// Returns `false` for flag API events until Configuration shared state is available and, when required
    /// config keys are present, the Flag extension shared state has resolved to `ready` or `failed`.
    ///
    /// EventHub holds the event at the front of this extension's serial queue while this returns `false`, and
    /// re-evaluates when shared state changes. Configuration, lifecycle, and all other events always return
    /// `true` so the extension queue cannot deadlock behind a blocked flag API event.
    public func readyForEvent(_ event: Event) -> Bool {
        guard isFlagApiRequest(event) else {
            return true
        }

        // 1. Configuration shared state must be available.
        guard let configData = getConfigurationData(event: event) else {
            return false
        }

        // 2. Config is set but required keys are missing → deliver the event so the handler can error
        //    deterministically instead of waiting indefinitely.
        if !FlagConfigurationProvider.hasRequiredConfig(configData) {
            return true
        }

        // 3 + 4. Required config present → wait for the Flag shared state to resolve (ready or failed).
        if !isFlagInitializationComplete(event: event) {
            // Required config is present but Flag shared state has not resolved yet. Start initialization from
            // the Configuration shared state this gate reads so flag API events are not blocked waiting for a
            // Configuration response event that may race with shared state updates.
            tryStartInitialization(event: event, configData: configData)
            return false
        }

        // Hold flag API events while Edge Identity shared state is pending (when Edge Identity is registered).
        return identityFetcher.isIdentityReady(extensionRuntime: runtime, event: event)
    }

    func handleConfigurationResponse(_ event: Event) {
        guard let configData = event.data, !configData.isEmpty else {
            return
        }

        if clientManager.isClientReady() {
            return
        }

        tryStartInitialization(event: event, configData: configData)
    }

    func handleFlagRequestContent(_ event: Event) {
        guard let eventData = event.data, !eventData.isEmpty else {
            return
        }

        if clientManager.isClientReady() {
            clientManager.processRequestEvent(event)
        } else {
            // Client is not ready — init failed or required config keys are missing. Deliver a deterministic error.
            clientManager.dispatchErrorResponse(event, error: .unexpected)
        }
    }

    func handleLifecycleEvent(_ event: Event) {
        guard let eventData = event.data else {
            return
        }

        guard let action = FlagDataReader.optString(eventData, key: FlagConstants.Lifecycle.actionKey) else {
            return
        }

        if action == FlagConstants.Lifecycle.actionStart {
            clientManager.handleAppStateChange(FlagsSDKAppState.foreground)
        } else if action == FlagConstants.Lifecycle.actionPause {
            clientManager.handleAppStateChange(FlagsSDKAppState.background)
        }
    }

    // MARK: - Private helpers

    private func isFlagApiRequest(_ event: Event) -> Bool {
        event.type.caseInsensitiveCompare(FlagConstants.EventType.flags) == .orderedSame &&
            event.source.caseInsensitiveCompare(FlagConstants.EventSource.requestContent) == .orderedSame
    }

    /// Returns Configuration shared state data only when it has been published (`.set`); otherwise `nil`.
    /// A `.set` but empty configuration resolves to `[:]` (distinct from "not yet available").
    private func getConfigurationData(event: Event?) -> [String: Any]? {
        let result = getSharedState(
            extensionName: FlagConstants.Configuration.extensionName,
            event: event,
            barrier: false
        )
        guard result?.status == .set else {
            return nil
        }
        return result?.value ?? [:]
    }

    /// Returns `true` once the Flag extension shared state has resolved to `ready` or `failed`.
    /// Uses `.lastSet` resolution so a resolved state is observed even if the current event predates it.
    private func isFlagInitializationComplete(event: Event) -> Bool {
        let flagSharedState = getSharedState(
            extensionName: FlagConstants.extensionName,
            event: event,
            barrier: false,
            resolution: .lastSet
        )
        guard flagSharedState?.status == .set,
              let status = flagSharedState?.value?[FlagConstants.SharedState.initializationStatus] as? String else {
            return false
        }
        return status == FlagConstants.SharedState.statusReady || status == FlagConstants.SharedState.statusFailed
    }

    /// Single initialization path shared by `onRegistered` (config peek) and `handleConfigurationResponse`.
    /// Creates a pending Flag shared state (the EventHub wake-up signal) and kicks off async client init.
    /// No-ops when the client is ready, init is already in flight, or required config keys are missing.
    private func tryStartInitialization(event: Event?, configData: [String: Any]) {
        if clientManager.isClientReady() || clientManager.isInitializationInProgress() {
            return
        }

        if !FlagConfigurationProvider.hasRequiredConfig(configData) {
            return
        }

        let resolver = createPendingSharedState(event: event)
        clientManager.startAsyncInitialization(configData: configData, resolver: resolver)
    }

    func getClientManager() -> FlagClientManager {
        clientManager
    }
}
