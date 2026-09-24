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
import Foundation

enum ExposureQueueTestSupport {
    static func createDeterministicQueue(flushCallback: @escaping ExposureFlushCallback) -> FeatureExposureQueue {
        createQueue(
            flushCallback: flushCallback,
            flushTimer: NoOpFlushTimer(),
            flushIntervalMs: FlagConstants.ExposureQueue.flushIntervalMs,
            batchSize: FlagConstants.ExposureQueue.batchSize
        )
    }

    static func createQueue(
        flushCallback: @escaping ExposureFlushCallback,
        flushTimer: FeatureExposureQueue.FlushTimer,
        flushIntervalMs: Int64,
        batchSize: Int
    ) -> FeatureExposureQueue {
        FeatureExposureQueue(
            flushCallback: flushCallback,
            workQueue: DispatchQueue(label: "FlagExposure-test"),
            flushTimer: flushTimer,
            flushIntervalMs: flushIntervalMs,
            batchSize: batchSize,
            executeOnCallerThread: true
        )
    }

    static func createWithScheduledTimer(
        flushCallback: @escaping ExposureFlushCallback,
        flushIntervalMs: Int64,
        batchSize: Int
    ) -> FeatureExposureQueue {
        let workQueue = DispatchQueue(label: "FlagExposure-scheduled-test")
        return FeatureExposureQueue(
            flushCallback: flushCallback,
            workQueue: workQueue,
            flushTimer: ScheduledFlushTimer(queue: workQueue),
            flushIntervalMs: flushIntervalMs,
            batchSize: batchSize,
            executeOnCallerThread: false
        )
    }

    static func createAsyncQueue(
        flushCallback: @escaping ExposureFlushCallback,
        flushTimer: FeatureExposureQueue.FlushTimer = NoOpFlushTimer()
    ) -> FeatureExposureQueue {
        FeatureExposureQueue(
            flushCallback: flushCallback,
            workQueue: DispatchQueue(label: "FlagExposure-async-test"),
            flushTimer: flushTimer,
            flushIntervalMs: FlagConstants.ExposureQueue.flushIntervalMs,
            batchSize: FlagConstants.ExposureQueue.batchSize,
            executeOnCallerThread: false
        )
    }
}

final class FlushRecorder {
    private(set) var flushes: [[AggregatedExposureEvent]] = []
    var onFlushAction: (() -> Void)?
    var failFirstFlush = false
    private var failedOnce = false
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var completionSignals = 0

    var callback: ExposureFlushCallback {
        { [weak self] events in
            guard let self else { return }
            if self.failFirstFlush, !self.failedOnce {
                self.failedOnce = true
                return
            }
            self.flushes.append(events)
            self.onFlushAction?()
            self.completionSignals += 1
            self.completionSemaphore.signal()
        }
    }

    func awaitCompletion(timeout: TimeInterval = 2.0) -> Bool {
        completionSemaphore.wait(timeout: .now() + timeout) == .success
    }
}

enum ExposureTestAssertions {
    static func isPropositionDisplayEdgeEvent(_ event: Event) -> Bool {
        guard event.type == EventType.edge,
              event.source == EventSource.requestContent else {
            return false
        }

        guard let xdm = event.data?[FlagConstants.Edge.xdm] as? [String: Any] else {
            return false
        }

        return xdm[FlagConstants.Edge.eventType] as? String == FlagConstants.Edge.eventTypePropositionDisplay
    }

    static func findEdgeEvent(_ events: [Event]) -> Event? {
        events.first { $0.type == EventType.edge }
    }

    static func countEdgeEvents(_ events: [Event]) -> Int {
        events.filter { isPropositionDisplayEdgeEvent($0) }.count
    }

    static func extractDisplayCount(_ edgeEvent: Event) -> Int {
        guard let xdm = edgeEvent.data?[FlagConstants.Edge.xdm] as? [String: Any],
              let experience = xdm[FlagConstants.Edge.experience] as? [String: Any],
              let decisioning = experience[FlagConstants.Edge.decisioning] as? [String: Any],
              let propositionEventType = decisioning[FlagConstants.Edge.propositionEventType] as? [String: Any],
              let display = propositionEventType[FlagConstants.Edge.display] as? NSNumber else {
            return -1
        }
        return display.intValue
    }

    static func extractCorrelationId(_ edgeEvent: Event) -> String? {
        guard let xdm = edgeEvent.data?[FlagConstants.Edge.xdm] as? [String: Any],
              let experience = xdm[FlagConstants.Edge.experience] as? [String: Any],
              let decisioning = experience[FlagConstants.Edge.decisioning] as? [String: Any],
              let propositions = decisioning[FlagConstants.Edge.propositions] as? [[String: Any]],
              let scopeDetails = propositions.first?[FlagConstants.Edge.scopeDetails] as? [String: Any] else {
            return nil
        }
        return scopeDetails[FlagConstants.Edge.correlationId] as? String
    }

    static func extractTimestamp(_ edgeEvent: Event) -> String? {
        guard let xdm = edgeEvent.data?[FlagConstants.Edge.xdm] as? [String: Any] else {
            return nil
        }
        return xdm[FlagConstants.Edge.timestamp] as? String
    }

    static func hasFeatureGroupItems(_ edgeEvent: Event) -> Bool {
        guard let xdm = edgeEvent.data?[FlagConstants.Edge.xdm] as? [String: Any],
              let experience = xdm[FlagConstants.Edge.experience] as? [String: Any],
              let decisioning = experience[FlagConstants.Edge.decisioning] as? [String: Any],
              let propositions = decisioning[FlagConstants.Edge.propositions] as? [[String: Any]] else {
            return false
        }
        return propositions.first?[FlagConstants.Edge.items] != nil
    }

    static func featureResultWithAnalytics(
        featureGroupId: Int,
        featureGroupKey: String,
        featureId: Int,
        featureKey: String,
        variantId: String
    ) -> FlagsSDKFeatureResult {
        FlagsSDKFeatureResult(
            id: featureId,
            key: featureKey,
            featureGroupKey: featureGroupKey,
            value: nil,
            meta: nil,
            analyticsParam: AnalyticsParam(
                featureGroupId: featureGroupId,
                featureId: featureId,
                featureKey: featureKey,
                variantId: variantId
            )
        )
    }
}
