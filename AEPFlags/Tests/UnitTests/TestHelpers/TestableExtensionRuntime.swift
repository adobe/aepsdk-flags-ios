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
import Foundation

public class TestableExtensionRuntime: ExtensionRuntime {
    public var listeners: [String: EventListener] = [:]
    public var dispatchedEvents: [Event] = []
    public var mockedSharedStates: [String: SharedStateResult] = [:]
    public var createdSharedStates: [[String: Any]?] = []

    /// When set, matching edge dispatch attempts throw before recording the event (batch isolation tests).
    public var failEdgeDispatchOnAttempts: Set<Int> = []
    public private(set) var edgeDispatchAttemptCount = 0

    /// Guards `dispatchedEvents`/`edgeDispatchAttemptCount` mutation only. Tests that exercise the extension
    /// from a single thread (the common case) are unaffected; tests that drive the extension concurrently
    /// (e.g. simulating parallel API callers) rely on this so appends to `dispatchedEvents` don't race.
    private let dispatchLock = NSLock()

    enum SimulatedEdgeDispatchError: Error {
        case simulatedFailure
    }

    // MARK: - Pending shared state capture

    /// Every `(event, resolver)` returned by `createPendingSharedState` is captured here so component tests
    /// can assert that a pending Flag shared state was created and drive its resolution.
    public var pendingSharedStateResolvers: [(Event?, SharedStateResolver)] = []

    /// Payloads passed to any resolver returned by `createPendingSharedState`.
    public var resolvedSharedStates: [[String: Any]] = []

    /// When set, resolving a pending shared state also publishes it as a `.set` mocked shared state under this
    /// name (defaults to the Flag extension owner). This makes `readyForEvent` observe the resolved state, mirroring
    /// real EventHub behavior where the resolved Flag shared state unblocks the held event.
    public var pendingSharedStateOwner: String? = "com.adobe.flags"

    /// Optional hook invoked after each pending shared state resolution (useful for `XCTestExpectation`).
    public var onResolvePendingSharedState: (([String: Any]) -> Void)?

    public init() {}

    public func unregisterExtension() {}

    public func registerListener(type: String, source: String, listener: @escaping EventListener) {
        listeners["\(type)-\(source)"] = listener
    }

    public func dispatch(event: Event) {
        dispatchLock.lock()
        dispatchedEvents.append(event)
        dispatchLock.unlock()
    }

    public func createSharedState(data: [String: Any], event _: Event?) {
        createdSharedStates.append(data)
        if let owner = pendingSharedStateOwner {
            mockedSharedStates[owner] = SharedStateResult(status: .set, value: data)
        }
    }

    public func createPendingSharedState(event: Event?) -> SharedStateResolver {
        let resolver: SharedStateResolver = { [weak self] data in
            guard let self else { return }
            let resolved = data ?? [:]
            self.resolvedSharedStates.append(resolved)
            if let owner = self.pendingSharedStateOwner {
                self.mockedSharedStates[owner] = SharedStateResult(status: .set, value: resolved)
            }
            self.onResolvePendingSharedState?(resolved)
        }
        pendingSharedStateResolvers.append((event, resolver))
        return resolver
    }

    public func getSharedState(extensionName: String, event: Event?, barrier _: Bool) -> SharedStateResult? {
        if let id = event?.id {
            return mockedSharedStates["\(extensionName)-\(id)"] ?? mockedSharedStates[extensionName]
        }
        return mockedSharedStates[extensionName]
    }

    public func createXDMSharedState(data: [String: Any], event _: Event?) {}

    public func createPendingXDMSharedState(event _: Event?) -> SharedStateResolver {
        { _ in }
    }

    public func getXDMSharedState(extensionName: String, event: Event?, barrier _: Bool) -> SharedStateResult? {
        mockedSharedStates[extensionName]
    }

    public func getSharedState(extensionName: String, event: Event?, barrier: Bool, resolution: SharedStateResolution) -> SharedStateResult? {
        getSharedState(extensionName: extensionName, event: event, barrier: barrier)
    }

    public func getXDMSharedState(extensionName: String, event: Event?, barrier: Bool, resolution: SharedStateResolution) -> SharedStateResult? {
        getXDMSharedState(extensionName: extensionName, event: event, barrier: barrier)
    }

    public func startEvents() {}

    public func stopEvents() {}

    public func getHistoricalEvents(_ requests: [EventHistoryRequest], enforceOrder: Bool, handler: @escaping ([EventHistoryResult]) -> Void) {
        handler([])
    }

    public func recordHistoricalEvent(_ event: Event, handler: ((Bool) -> Void)?) {
        handler?(true)
    }
}

extension TestableExtensionRuntime: FlagExposureEdgeDispatchingOverride {
    public func dispatchExposureEdgeEventOverride(_ event: Event) throws {
        dispatchLock.lock()
        defer { dispatchLock.unlock() }
        if event.type == EventType.edge {
            edgeDispatchAttemptCount += 1
            if failEdgeDispatchOnAttempts.contains(edgeDispatchAttemptCount) {
                throw SimulatedEdgeDispatchError.simulatedFailure
            }
        }
        dispatchedEvents.append(event)
    }
}
