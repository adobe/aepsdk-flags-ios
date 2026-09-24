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
import XCTest

class FeatureExposureQueueTests: XCTestCase {
    private let flushIntervalMs = FlagConstants.ExposureQueue.flushIntervalMs
    private let batchSize = FlagConstants.ExposureQueue.batchSize

    private var flushRecorder: FlushRecorder!
    private var manualFlushTimer: ManualFlushTimer!
    private var queue: FeatureExposureQueue!

    override func setUp() {
        flushRecorder = FlushRecorder()
        manualFlushTimer = ManualFlushTimer()
        queue = ExposureQueueTestSupport.createQueue(
            flushCallback: flushRecorder.callback,
            flushTimer: manualFlushTimer,
            flushIntervalMs: flushIntervalMs,
            batchSize: batchSize
        )
    }

    override func tearDown() {
        queue.shutdown()
        _ = queue.awaitShutdown(timeout: 2.0)
    }

    private func standaloneFeature(featureId: Int, featureKey: String, variantId: String) -> FlagsSDKFeatureResult {
        ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: -1,
            featureGroupKey: FlagConstants.Edge.standaloneFeaturesFeatureGroupKey,
            featureId: featureId,
            featureKey: featureKey,
            variantId: variantId
        )
    }

    private func enqueueUnique(_ index: Int, evaluatedAtMillis: Int64) {
        let feature = standaloneFeature(featureId: index, featureKey: "feature-\(index)", variantId: "v\(index)")
        let aggregationKey = ExposureEventIdGenerator.generateAggregationKey(feature)!
        queue.enqueue(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: evaluatedAtMillis)
    }

    private func enqueueOn(
        _ targetQueue: FeatureExposureQueue,
        index: Int,
        evaluatedAtMillis: Int64,
        aggregationKey: String,
        feature: FlagsSDKFeatureResult
    ) {
        targetQueue.enqueue(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: evaluatedAtMillis)
    }

    private func enqueueUniqueOn(_ targetQueue: FeatureExposureQueue, index: Int, evaluatedAtMillis: Int64) {
        let feature = standaloneFeature(featureId: index, featureKey: "feature-\(index)", variantId: "10283012")
        enqueueOn(
            targetQueue,
            index: index,
            evaluatedAtMillis: evaluatedAtMillis,
            aggregationKey: "F-\(index)-10283012",
            feature: feature
        )
    }

    private func shutdownQueue(_ targetQueue: FeatureExposureQueue) {
        targetQueue.shutdown()
        _ = targetQueue.awaitShutdown(timeout: 2.0)
    }

    func testEnqueue_firstEvent_schedulesTimerWithConfiguredInterval() {
        enqueueUnique(1, evaluatedAtMillis: 100)

        XCTAssertTrue(manualFlushTimer.isScheduled)
        XCTAssertEqual(flushIntervalMs, manualFlushTimer.delayMs)
        XCTAssertTrue(flushRecorder.flushes.isEmpty)
    }

    func testTimerFlush_dispatchesAggregatedPendingEvents() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        enqueueUnique(2, evaluatedAtMillis: 200)
        enqueueUnique(3, evaluatedAtMillis: 300)

        manualFlushTimer.fire()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(3, flushRecorder.flushes[0].count)
        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testBatchSizeReached_flushesImmediatelyBeforeTimer() {
        for index in 1...batchSize {
            enqueueUnique(index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(batchSize, flushRecorder.flushes[0].count)
        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testTwentyFiveUniqueAggregationKeys_flushesTwentyThenFive() {
        for index in 1...25 {
            enqueueUnique(index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(batchSize, flushRecorder.flushes[0].count)

        queue.flush()

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(5, flushRecorder.flushes[1].count)
    }

    func testDuplicateAggregationKey_aggregatesDisplayCountAndLastTimestamp() {
        let feature = standaloneFeature(featureId: 173226, featureKey: "checkout-flag", variantId: "10283012")
        let aggregationKey = "F-173226-10283012"

        for index in 1...40 {
            queue.enqueue(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: Int64(index * 100))
        }

        queue.flush()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        let event = flushRecorder.flushes[0].first
        XCTAssertEqual(40, event?.displayCount)
        XCTAssertEqual(4000, event?.lastEvaluatedAtMillis)
    }

    func testEmptyAggregationKey_isIgnored() {
        let feature = standaloneFeature(featureId: 1, featureKey: "feature-a", variantId: "v1")
        queue.enqueue(aggregationKey: "", feature: feature, evaluatedAtMillis: 100)
        queue.flush()
        XCTAssertTrue(flushRecorder.flushes.isEmpty)
    }

    func testExplicitFlushWithEmptyQueue_doesNotInvokeCallback() {
        queue.flush()
        XCTAssertTrue(flushRecorder.flushes.isEmpty)
    }

    func testShutdown_flushesPendingEvents() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.shutdown()
        XCTAssertTrue(queue.awaitShutdown(timeout: 2.0))
        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[0].count)
    }

    func testShutdown_rejectsSubsequentEnqueues() {
        let featureA = standaloneFeature(featureId: 1, featureKey: "feature-a", variantId: "10283012")
        queue.enqueue(aggregationKey: "F-1-10283012", feature: featureA, evaluatedAtMillis: 100)

        queue.shutdown()
        _ = queue.awaitShutdown(timeout: 2.0)

        let featureB = standaloneFeature(featureId: 2, featureKey: "feature-b", variantId: "10283012")
        queue.enqueue(aggregationKey: "F-2-10283012", feature: featureB, evaluatedAtMillis: 200)
        queue.flush()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[0].count)
        XCTAssertEqual("F-1-10283012", flushRecorder.flushes[0].first?.aggregationKey)
    }

    private func featureGroupFeature(
        featureGroupId: Int,
        featureId: Int,
        featureKey: String,
        variantId: String,
        featureGroupKey: String = "fg-group"
    ) -> FlagsSDKFeatureResult {
        ExposureTestAssertions.featureResultWithAnalytics(
            featureGroupId: featureGroupId,
            featureGroupKey: featureGroupKey,
            featureId: featureId,
            featureKey: featureKey,
            variantId: variantId
        )
    }

    func testFeatureGroupDistinctFeatures_sameVariant_aggregateSeparately() {
        let featureA = featureGroupFeature(featureGroupId: 23261, featureId: 1, featureKey: "feature-a", variantId: "10283012")
        let featureB = featureGroupFeature(featureGroupId: 23261, featureId: 2, featureKey: "feature-b", variantId: "10283012")

        queue.enqueue(aggregationKey: "FG-23261-1-10283012", feature: featureA, evaluatedAtMillis: 100)
        queue.enqueue(aggregationKey: "FG-23261-2-10283012", feature: featureB, evaluatedAtMillis: 200)
        queue.enqueue(aggregationKey: "FG-23261-1-10283012", feature: featureA, evaluatedAtMillis: 300)
        queue.flush()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(2, flushRecorder.flushes[0].count)

        var first = flushRecorder.flushes[0][0]
        var second = flushRecorder.flushes[0][1]
        if first.aggregationKey == "FG-23261-2-10283012" {
            (first, second) = (second, first)
        }

        XCTAssertEqual("FG-23261-1-10283012", first.aggregationKey)
        XCTAssertEqual(2, first.displayCount)
        XCTAssertEqual("feature-a", first.feature.key)
        XCTAssertEqual("FG-23261-2-10283012", second.aggregationKey)
        XCTAssertEqual(1, second.displayCount)
        XCTAssertEqual("feature-b", second.feature.key)
    }

    func testFlushRequestedWhileFlushInProgress_coalescesIntoChainedFlush() {
        let extraFeature = standaloneFeature(featureId: 999, featureKey: "extra-flag", variantId: "10283012")
        flushRecorder.onFlushAction = { [weak self] in
            guard let self else { return }
            if self.flushRecorder.flushes.count == 1 {
                self.queue.enqueue(aggregationKey: "F-999-10283012", feature: extraFeature, evaluatedAtMillis: 999)
                self.queue.flush()
            }
        }

        for index in 1...batchSize {
            enqueueUnique(index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(batchSize, flushRecorder.flushes[0].count)
        XCTAssertEqual(1, flushRecorder.flushes[1].count)
        XCTAssertEqual("F-999-10283012", flushRecorder.flushes[1].first?.aggregationKey)
    }

    func testEnqueueDuringFlush_isIncludedInNextFlushBatch() {
        let duringFlushFeature = standaloneFeature(featureId: 999, featureKey: "during-flush", variantId: "10283012")
        flushRecorder.onFlushAction = { [weak self] in
            guard let self else { return }
            if self.flushRecorder.flushes.count == 1 {
                self.queue.enqueue(aggregationKey: "F-999-10283012", feature: duringFlushFeature, evaluatedAtMillis: 999)
            }
        }

        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.flush()

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[0].count)
        XCTAssertEqual(1, flushRecorder.flushes[1].count)
        XCTAssertEqual("F-999-10283012", flushRecorder.flushes[1].first?.aggregationKey)
    }

    func testAfterFlush_sameAggregationKeyCanBeEnqueuedAgain() {
        let feature = standaloneFeature(featureId: 173226, featureKey: "checkout-flag", variantId: "10283012")
        let aggregationKey = "F-173226-10283012"

        queue.enqueue(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: 100)
        queue.flush()
        queue.enqueue(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: 200)
        queue.flush()

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[0].first?.displayCount)
        XCTAssertEqual(100, flushRecorder.flushes[0].first?.lastEvaluatedAtMillis)
        XCTAssertEqual(1, flushRecorder.flushes[1].first?.displayCount)
        XCTAssertEqual(200, flushRecorder.flushes[1].first?.lastEvaluatedAtMillis)
    }

    func testBatchFlush_doesNotKeepTimerRunningWhenQueueDrains() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        XCTAssertTrue(manualFlushTimer.isScheduled)

        for index in 2...batchSize {
            enqueueUnique(index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testPausePeriodicFlush_cancelsScheduledTimer() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        XCTAssertTrue(manualFlushTimer.isScheduled)

        queue.pausePeriodicFlush()

        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testResumePeriodicFlush_restartsTimerWhenPendingWorkRemains() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.pausePeriodicFlush()
        XCTAssertFalse(manualFlushTimer.isScheduled)

        queue.resumePeriodicFlush()

        XCTAssertTrue(manualFlushTimer.isScheduled)
    }

    func testResumePeriodicFlush_doesNotScheduleTimerWhenQueueIsIdle() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.flush()
        queue.pausePeriodicFlush()

        queue.resumePeriodicFlush()

        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testFlushCallbackFailure_stillAllowsSubsequentFlush() {
        flushRecorder.failFirstFlush = true

        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.flush()
        enqueueUnique(2, evaluatedAtMillis: 200)
        queue.flush()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual("F-2-v2", flushRecorder.flushes[0].first?.aggregationKey)
    }

    func testFlush_afterShutdown_isNoOp() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.shutdown()
        _ = queue.awaitShutdown(timeout: 2.0)

        queue.flush()

        XCTAssertEqual(1, flushRecorder.flushes.count)
    }

    func testPausePeriodicFlush_afterShutdown_isNoOp() {
        queue.shutdown()
        _ = queue.awaitShutdown(timeout: 2.0)

        queue.pausePeriodicFlush()

        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testResumePeriodicFlush_afterShutdown_isNoOp() {
        queue.shutdown()
        _ = queue.awaitShutdown(timeout: 2.0)

        queue.resumePeriodicFlush()

        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testShutdown_isIdempotent() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        queue.shutdown()
        queue.shutdown()
        XCTAssertTrue(queue.awaitShutdown(timeout: 2.0))
        XCTAssertEqual(1, flushRecorder.flushes.count)
    }

    func testPeriodicTimer_restartsOnNewEnqueueAfterIdleFlush() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        enqueueUnique(2, evaluatedAtMillis: 200)
        manualFlushTimer.fire()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertEqual(2, flushRecorder.flushes[0].count)
        XCTAssertFalse(manualFlushTimer.isScheduled)

        enqueueUnique(3, evaluatedAtMillis: 300)
        XCTAssertTrue(manualFlushTimer.isScheduled)
        manualFlushTimer.fire()

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[1].count)
        XCTAssertFalse(manualFlushTimer.isScheduled)
    }

    func testIdleTimerDoesNotRescheduleWithoutPendingWork() {
        enqueueUnique(1, evaluatedAtMillis: 100)
        manualFlushTimer.fire()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertFalse(manualFlushTimer.isScheduled)

        manualFlushTimer.fire()

        XCTAssertEqual(1, flushRecorder.flushes.count)
        XCTAssertFalse(manualFlushTimer.isScheduled)

        enqueueUnique(2, evaluatedAtMillis: 200)
        XCTAssertTrue(manualFlushTimer.isScheduled)
        manualFlushTimer.fire()

        XCTAssertEqual(2, flushRecorder.flushes.count)
        XCTAssertEqual(1, flushRecorder.flushes[1].count)
    }

    func testScheduledTimerFlush_firesAfterConfiguredDelay_withoutManualFlush() {
        let scheduledRecorder = FlushRecorder()
        let scheduledQueue = ExposureQueueTestSupport.createWithScheduledTimer(
            flushCallback: scheduledRecorder.callback,
            flushIntervalMs: 100,
            batchSize: batchSize
        )
        defer { shutdownQueue(scheduledQueue) }

        enqueueOn(
            scheduledQueue,
            index: 1,
            evaluatedAtMillis: 100,
            aggregationKey: "F-1-10283012",
            feature: standaloneFeature(featureId: 1, featureKey: "feature-1", variantId: "10283012")
        )
        enqueueOn(
            scheduledQueue,
            index: 2,
            evaluatedAtMillis: 200,
            aggregationKey: "F-2-10283012",
            feature: standaloneFeature(featureId: 2, featureKey: "feature-2", variantId: "10283012")
        )

        XCTAssertTrue(scheduledRecorder.awaitCompletion(timeout: 2.0))
        XCTAssertEqual(1, scheduledRecorder.flushes.count)
        XCTAssertEqual(2, scheduledRecorder.flushes[0].count)
    }

    func testScheduledTimerFlush_waitsUntilIntervalWhenBatchNotFull() {
        let scheduledRecorder = FlushRecorder()
        let scheduledQueue = ExposureQueueTestSupport.createWithScheduledTimer(
            flushCallback: scheduledRecorder.callback,
            flushIntervalMs: 150,
            batchSize: batchSize
        )
        defer { shutdownQueue(scheduledQueue) }

        for index in 1...19 {
            enqueueUniqueOn(scheduledQueue, index: index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertFalse(scheduledRecorder.awaitCompletion(timeout: 0.05))
        XCTAssertTrue(scheduledRecorder.awaitCompletion(timeout: 2.0))
        XCTAssertEqual(1, scheduledRecorder.flushes.count)
        XCTAssertEqual(19, scheduledRecorder.flushes[0].count)
    }

    func testBatchSizeReachedBeforeScheduledTimer_firesImmediately() {
        let scheduledRecorder = FlushRecorder()
        let scheduledQueue = ExposureQueueTestSupport.createWithScheduledTimer(
            flushCallback: scheduledRecorder.callback,
            flushIntervalMs: 500,
            batchSize: batchSize
        )
        defer { shutdownQueue(scheduledQueue) }

        for index in 1...batchSize {
            enqueueUniqueOn(scheduledQueue, index: index, evaluatedAtMillis: Int64(index * 10))
        }

        XCTAssertTrue(scheduledRecorder.awaitCompletion(timeout: 0.2))
        XCTAssertEqual(1, scheduledRecorder.flushes.count)
        XCTAssertEqual(batchSize, scheduledRecorder.flushes[0].count)
    }

    func testScheduledPeriodicFlush_firesSecondWindowAfterReschedule() {
        let scheduledRecorder = FlushRecorder()
        let scheduledQueue = ExposureQueueTestSupport.createWithScheduledTimer(
            flushCallback: scheduledRecorder.callback,
            flushIntervalMs: 100,
            batchSize: batchSize
        )
        defer { shutdownQueue(scheduledQueue) }

        enqueueOn(
            scheduledQueue,
            index: 1,
            evaluatedAtMillis: 100,
            aggregationKey: "F-1-10283012",
            feature: standaloneFeature(featureId: 1, featureKey: "feature-1", variantId: "10283012")
        )

        XCTAssertTrue(scheduledRecorder.awaitCompletion(timeout: 2.0))
        XCTAssertEqual(1, scheduledRecorder.flushes.count)

        enqueueOn(
            scheduledQueue,
            index: 2,
            evaluatedAtMillis: 200,
            aggregationKey: "F-2-10283012",
            feature: standaloneFeature(featureId: 2, featureKey: "feature-2", variantId: "10283012")
        )

        XCTAssertTrue(scheduledRecorder.awaitCompletion(timeout: 2.0))
        XCTAssertEqual(2, scheduledRecorder.flushes.count)
        XCTAssertEqual(1, scheduledRecorder.flushes[1].count)
    }
}
