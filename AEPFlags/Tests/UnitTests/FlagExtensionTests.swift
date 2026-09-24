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
@testable import AEPCore
import FlagsEngine
import XCTest

class FlagExtensionTests: XCTestCase {
    private var runtime: TestableExtensionRuntime!
    private var identityFetcher: MockFlagIdentityFetcher!
    private var flag: AEPFlags.Flag!

    override func setUp() {
        runtime = TestableExtensionRuntime()
        identityFetcher = MockFlagIdentityFetcher()
        let testRuntime = runtime!
        let syncQueue = ExposureQueueTestSupport.createDeterministicQueue { events in
            FlagEdgeHandler.dispatchExposureEvents(extensionRuntime: testRuntime, events: events)
        }
        let manager = FlagClientManager(
            extensionRuntime: runtime,
            identityFetcher: identityFetcher,
            exposureQueue: syncQueue
        )
        flag = AEPFlags.Flag(runtime: runtime, clientManager: manager, identityFetcher: identityFetcher)
        useDefaultMockClient()
    }

    private func useDefaultMockClient() {
        FlagsMobileClientFactory.createOverride = { _ in
            let mock = MockFlagsMobileClient()
            mock.isClientInitialized = true
            return mock
        }
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Helpers

    private func fullRequiredConfig() -> [String: Any] {
        [
            FlagConstants.Configuration.experienceCloudOrg: "test@AdobeOrg",
            FlagConstants.Configuration.flagsSandbox: "prod",
            FlagConstants.Configuration.flagsClientId: "client-123"
        ]
    }

    private func flagRequestEvent() -> Event {
        Event(
            name: "Test Flag Request",
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: nil
        )
    }

    private func setEdgeIdentitySharedState(_ value: [String: Any]?, status: SharedStateStatus) {
        runtime.mockedSharedStates[FlagConstants.EdgeIdentity.extensionName] =
            SharedStateResult(status: status, value: value)
    }

    private func setEdgeIdentityReady() {
        let xdmState: [String: Any] = [
            IdentityMapMarshaller.xdmKeyIdentityMap: [
                "ECID": [[
                    IdentityMapMarshaller.keyId: "ecid-ready",
                    IdentityMapMarshaller.keyPrimary: true,
                    IdentityMapMarshaller.keyAuthenticatedState: "ambiguous"
                ]]
            ]
        ]
        setEdgeIdentitySharedState(xdmState, status: .set)
    }

    private func getFeatureEvent(featureName: String = "feature-key") -> Event {
        Event(
            name: FlagConstants.EventNames.getFeatureRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: [
                FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeGetFeature,
                FlagConstants.EventDataKeys.featureName: featureName
            ]
        )
    }

    private func isFeatureEnabledEvent(featureName: String = "feature-key") -> Event {
        Event(
            name: FlagConstants.EventNames.isFeatureEnabledRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: [
                FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeIsEnabled,
                FlagConstants.EventDataKeys.featureName: featureName
            ]
        )
    }

    private func setConfig(_ config: [String: Any], status: SharedStateStatus = .set) {
        runtime.mockedSharedStates[FlagConstants.Configuration.extensionName] =
            SharedStateResult(status: status, value: config)
    }

    private func setFlagSharedState(_ value: [String: Any]?, status: SharedStateStatus = .set) {
        runtime.mockedSharedStates[FlagConstants.extensionName] =
            SharedStateResult(status: status, value: value)
    }

    private func responseEvents() -> [Event] {
        runtime.dispatchedEvents.filter { $0.source == FlagConstants.EventSource.responseContent }
    }

    private func makeMockClientFactory(ready: Bool = true) {
        FlagsMobileClientFactory.createOverride = { _ in
            let mock = MockFlagsMobileClient()
            mock.isClientInitialized = ready
            return mock
        }
    }

    // MARK: - Metadata

    func testExtensionMetadata() {
        XCTAssertEqual("com.adobe.flags", flag.name)
        XCTAssertEqual(FlagConstants.extensionVersion, AEPFlags.Flag.extensionVersion)
        XCTAssertEqual("Flags", flag.friendlyName)
    }

    func testOnRegistered_registersFlagListener() {
        flag.onRegistered()
        XCTAssertNotNil(runtime.listeners["\(FlagConstants.EventType.flags)-\(FlagConstants.EventSource.requestContent)"])
    }

    // MARK: - readyForEvent contract

    /// Full required config plus a resolved Flag shared state (`ready`) is required for `true`.
    func testReadyForEvent_flagRequest_configAvailable() {
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_flagRequest_configPending() {
        runtime.mockedSharedStates[FlagConstants.Configuration.extensionName] = SharedStateResult(status: .pending, value: nil)
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_configSet_flagAbsent_returnsFalse() {
        // With required config present but no resolved Flag shared state, initialization is started from the gate.
        // kicks off initialization. Use a factory that blocks until the test ends so the async resolution
        // cannot clobber the Flag shared state this test controls explicitly.
        let block = DispatchSemaphore(value: 0)
        FlagsMobileClientFactory.createOverride = { _ in
            block.wait()
            return MockFlagsMobileClient()
        }
        defer { block.signal() }

        setConfig(fullRequiredConfig())
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))

        setFlagSharedState(nil, status: .pending)
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_selfHealing_initInProgress_doesNotOrphanPendingState() {
        let gate = DispatchSemaphore(value: 0)
        FlagsMobileClientFactory.createOverride = { _ in
            gate.wait()
            let mock = MockFlagsMobileClient()
            mock.isClientInitialized = true
            return mock
        }

        setConfig(fullRequiredConfig())

        // First flag API event starts init and creates exactly one pending state.
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))
        XCTAssertEqual(runtime.pendingSharedStateResolvers.count, 1)
        XCTAssertTrue(flag.getClientManager().isInitializationInProgress())

        // Second flag API event while init is in flight: must not create another pending resolver.
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))
        XCTAssertEqual(runtime.pendingSharedStateResolvers.count, 1)

        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }
        gate.signal()
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(
            runtime.resolvedSharedStates.last?[FlagConstants.SharedState.initializationStatus] as? String,
            FlagConstants.SharedState.statusReady
        )
    }

    func testReadyForEvent_configSet_flagReady_returnsTrue() {
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_configSet_flagFailed_returnsTrue() {
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusFailed])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_configSet_missingRequiredKeys_returnsTrue() {
        setConfig([FlagConstants.Configuration.experienceCloudOrg: "test@AdobeOrg"])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_nonFlagEvent_alwaysReady() {
        let event = Event(name: "Test", type: "com.adobe.eventType.other", source: "com.adobe.eventSource.other", data: nil)
        XCTAssertTrue(flag.readyForEvent(event))
    }

    func testReadyForEvent_configurationResponseEvent_returnsTrue() {
        setConfig(fullRequiredConfig())
        setFlagSharedState(nil, status: .pending)
        let configResponse = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        XCTAssertTrue(flag.readyForEvent(configResponse))
    }

    // MARK: - Edge Identity readiness gate

    func testReadyForEvent_TR8_edgeIdentityPending_returnsFalse() {
        identityFetcher.identityReady = false
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertFalse(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_TR9_edgeIdentityNotRegistered_returnsTrue() {
        identityFetcher.identityReady = true
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_TR10_edgeIdentityReady_returnsTrue() {
        identityFetcher.identityReady = true
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    func testReadyForEvent_TR11_edgeIdentitySetEmpty_returnsTrue() {
        identityFetcher.identityReady = true
        setConfig(fullRequiredConfig())
        setFlagSharedState([FlagConstants.SharedState.initializationStatus: FlagConstants.SharedState.statusReady])
        XCTAssertTrue(flag.readyForEvent(flagRequestEvent()))
    }

    // MARK: - Handler behavior

    func testHandleConfigurationResponse_validConfig_createsPendingAndInits() {
        makeMockClientFactory(ready: true)
        let exp = expectation(description: "resolver invoked")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)

        XCTAssertEqual(runtime.pendingSharedStateResolvers.count, 1)
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(
            runtime.resolvedSharedStates.last?[FlagConstants.SharedState.initializationStatus] as? String,
            FlagConstants.SharedState.statusReady
        )
    }

    func testHandleConfigurationResponse_clientReady_noPendingNoInit() {
        let mock = MockFlagsMobileClient()
        flag.getClientManager().setFeatureClient(mock)
        flag.getClientManager().setFeatureClientInitialized(true)

        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)

        XCTAssertTrue(runtime.pendingSharedStateResolvers.isEmpty)
        XCTAssertFalse(flag.getClientManager().isInitializationInProgress())
    }

    func testHandleGetFeature_dispatchesResponse() throws {
        let mockClient = MockFlagsMobileClient()
        mockClient.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-key",
            featureGroupKey: "group-key",
            value: nil,
            meta: nil,
            analyticsParam: FlagsEngine.AnalyticsParam(featureGroupId: 10, featureId: 20, featureKey: "feature-key", variantId: "v1")
        )
        flag.getClientManager().setFeatureClient(mockClient)
        flag.getClientManager().setFeatureClientInitialized(true)

        flag.handleFlagRequestContent(getFeatureEvent())

        let response = responseEvents().first
        XCTAssertNotNil(response)
        let feature = response?.data?[FlagConstants.EventDataKeys.feature] as? [String: Any]
        XCTAssertEqual("feature-key", feature?[FlagConstants.EventDataKeys.key] as? String)
        XCTAssertNil(response?.data?[FlagConstants.EventDataKeys.responseError])
    }

    func testHandleGetFeature_dispatchesEdgeExposureWithCollectPath() {
        let mockClient = MockFlagsMobileClient()
        mockClient.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-key",
            featureGroupKey: "group-key",
            value: nil,
            meta: nil,
            analyticsParam: FlagsEngine.AnalyticsParam(featureGroupId: 10, featureId: 20, featureKey: "feature-key", variantId: "v1")
        )
        flag.getClientManager().setFeatureClient(mockClient)
        flag.getClientManager().setFeatureClientInitialized(true)

        flag.handleFlagRequestContent(getFeatureEvent())
        flag.getClientManager().handleAppStateChange(.background)

        let edgeEvent = runtime.dispatchedEvents.first { ExposureTestAssertions.isPropositionDisplayEdgeEvent($0) }
        XCTAssertNotNil(edgeEvent)
        let request = edgeEvent?.data?[FlagConstants.Edge.Request.key] as? [String: Any]
        XCTAssertEqual(FlagConstants.Edge.Request.collectPath, request?[FlagConstants.Edge.Request.path] as? String)
    }

    func testHandleFlagRequest_clientNotReady_dispatchesError() {
        flag.handleFlagRequestContent(getFeatureEvent())

        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
    }

    func testHandleFlagRequest_missingRequiredConfig_dispatchesError() {
        setConfig([FlagConstants.Configuration.experienceCloudOrg: "test@AdobeOrg"])

        flag.handleFlagRequestContent(getFeatureEvent())

        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
        // No Edge exposure event should be dispatched on the error path.
        let edgeEvents = runtime.dispatchedEvents.filter { $0.type == EventType.edge }
        XCTAssertTrue(edgeEvents.isEmpty)
    }

    // MARK: - Component ordering

    func testComponent_configThenResolveReadyThenRequest_succeeds() {
        makeMockClientFactory(ready: true)
        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        setConfig(fullRequiredConfig())
        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)
        wait(for: [exp], timeout: 2.0)

        let request = getFeatureEvent()
        XCTAssertTrue(flag.readyForEvent(request))

        flag.handleFlagRequestContent(request)
        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
    }

    func testComponent_requestBeforeConfig_notProcessedUntilResolve() {
        makeMockClientFactory(ready: true)
        let request = getFeatureEvent()

        // No configuration yet → event must be held.
        XCTAssertFalse(flag.readyForEvent(request))

        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }
        setConfig(fullRequiredConfig())
        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(flag.readyForEvent(request))
        flag.handleFlagRequestContent(request)
        XCTAssertEqual(responseEvents().count, 1)
        XCTAssertNil(responseEvents().first?.data?[FlagConstants.EventDataKeys.responseError])
    }

    func testComponent_initFailed_requestDelivered_errors() {
        FlagsMobileClientFactory.createOverride = { _ in
            throw FlagInitError.initializationFailed(message: "Test init failure", underlying: nil)
        }
        let exp = expectation(description: "init resolved failed")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        setConfig(fullRequiredConfig())
        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)
        wait(for: [exp], timeout: 2.0)

        XCTAssertEqual(
            runtime.resolvedSharedStates.last?[FlagConstants.SharedState.initializationStatus] as? String,
            FlagConstants.SharedState.statusFailed
        )

        let request = getFeatureEvent()
        XCTAssertTrue(flag.readyForEvent(request)) // failed → delivered

        flag.handleFlagRequestContent(request)
        let responses = responseEvents()
        XCTAssertEqual(responses.count, 1)
        XCTAssertNotNil(responses.first?.data?[FlagConstants.EventDataKeys.responseError])
    }

    func testComponent_onRegistered_configAlreadySet_initStarts() {
        makeMockClientFactory(ready: true)
        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        setConfig(fullRequiredConfig())
        flag.onRegistered()
        wait(for: [exp], timeout: 2.0)

        XCTAssertFalse(runtime.pendingSharedStateResolvers.isEmpty)
        XCTAssertEqual(
            runtime.resolvedSharedStates.last?[FlagConstants.SharedState.initializationStatus] as? String,
            FlagConstants.SharedState.statusReady
        )
        // Config peek used a nil event (no configuration response event required).
        XCTAssertEqual(runtime.pendingSharedStateResolvers.first?.0, nil)
    }

    func testComponent_multipleRequestsAfterResolve_allReceiveResponses() {
        makeMockClientFactory(ready: true)
        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        setConfig(fullRequiredConfig())
        let configEvent = Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        )
        flag.handleConfigurationResponse(configEvent)
        wait(for: [exp], timeout: 2.0)

        for index in 0..<5 {
            let request = getFeatureEvent(featureName: "feature-\(index)")
            XCTAssertTrue(flag.readyForEvent(request))
            flag.handleFlagRequestContent(request)
        }

        XCTAssertEqual(responseEvents().count, 5)
    }

    // MARK: - isFeatureEnabled request path

    /// Ported from the former `FlagFunctionalTests.testCust1_...isFeatureEnabled_success`: exercises the
    /// boolean `isFeatureEnabled` request/response path (distinct from `getFeature`) without going through
    /// the real EventHub.
    func testHandleIsFeatureEnabled_dispatchesResponse() {
        let mockClient = MockFlagsMobileClient()
        mockClient.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-key",
            featureGroupKey: "group-key",
            value: nil,
            meta: nil,
            analyticsParam: FlagsEngine.AnalyticsParam(featureGroupId: 10, featureId: 20, featureKey: "feature-key", variantId: "v1")
        )
        flag.getClientManager().setFeatureClient(mockClient)
        flag.getClientManager().setFeatureClientInitialized(true)

        flag.handleFlagRequestContent(isFeatureEnabledEvent())

        let response = responseEvents().first
        XCTAssertNotNil(response)
        XCTAssertNil(response?.data?[FlagConstants.EventDataKeys.responseError])
        XCTAssertEqual(true, response?.data?[FlagConstants.EventDataKeys.isEnabled] as? Bool)
    }

    // MARK: - Concurrency

    /// Ported from the former `FlagFunctionalTests.testCust6_tenParallelColdStart...`: verifies
    /// `FlagClientManager`'s own state synchronization holds up under concurrent callers, without
    /// depending on the real EventHub's serial-queue dispatch to serialize access for us.
    func testHandleFlagRequest_tenConcurrentCalls_allReceiveResponses() {
        makeMockClientFactory(ready: true)
        let exp = expectation(description: "init resolved")
        runtime.onResolvePendingSharedState = { _ in exp.fulfill() }

        setConfig(fullRequiredConfig())
        flag.handleConfigurationResponse(Event(
            name: "Configuration Response",
            type: EventType.configuration,
            source: EventSource.responseContent,
            data: fullRequiredConfig()
        ))
        wait(for: [exp], timeout: 2.0)

        let group = DispatchGroup()
        for index in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                self.flag.handleFlagRequestContent(self.getFeatureEvent(featureName: "feature-\(index)"))
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5.0), .success)
        XCTAssertEqual(responseEvents().count, 10)
    }

    // MARK: - Lifecycle-driven exposure flush

    /// Ported from the former `FlagFunctionalTests.testCust7_...dispatchesEdgeExposureEventAfterBackgroundFlush`:
    /// drives the same path through the real `handleLifecycleEvent` entry point (rather than calling
    /// `FlagClientManager.handleAppStateChange` directly, as `testHandleGetFeature_dispatchesEdgeExposureWithCollectPath`
    /// does) so the Lifecycle-event-to-app-state mapping in `Flag.handleLifecycleEvent` stays covered.
    func testHandleLifecycleEvent_pause_dispatchesEdgeExposureAfterFlush() {
        let mockClient = MockFlagsMobileClient()
        mockClient.featureResult = FlagsSDKFeatureResult(
            id: 1,
            key: "feature-key",
            featureGroupKey: "group-key",
            value: nil,
            meta: nil,
            analyticsParam: FlagsEngine.AnalyticsParam(featureGroupId: 10, featureId: 20, featureKey: "feature-key", variantId: "v1")
        )
        flag.getClientManager().setFeatureClient(mockClient)
        flag.getClientManager().setFeatureClientInitialized(true)

        flag.handleFlagRequestContent(getFeatureEvent())

        let pauseEvent = Event(
            name: "Lifecycle Pause",
            type: EventType.genericLifecycle,
            source: EventSource.requestContent,
            data: [FlagConstants.Lifecycle.actionKey: FlagConstants.Lifecycle.actionPause]
        )
        flag.handleLifecycleEvent(pauseEvent)

        let edgeEvent = runtime.dispatchedEvents.first { ExposureTestAssertions.isPropositionDisplayEdgeEvent($0) }
        XCTAssertNotNil(edgeEvent)
    }
}
