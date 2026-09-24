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

import AEPServices
import Foundation

typealias ExposureFlushCallback = ([AggregatedExposureEvent]) -> Void

/// Batches feature exposure events by aggregation key and flushes on batch size, periodic interval,
/// explicit request, lifecycle pause, or shutdown.
final class FeatureExposureQueue {
    private static let selfTag = "FeatureExposureQueue"

    protocol FlushTimer: AnyObject {
        func schedule(delayMs: Int64, task: @escaping () -> Void)
        func cancel()
        var isScheduled: Bool { get }
    }

    private let flushCallback: ExposureFlushCallback
    private let flushTimer: FlushTimer
    private let flushIntervalMs: Int64
    private let batchSize: Int
    private let executeOnCallerThread: Bool
    private let workQueue: DispatchQueue

    private let inboundLock = NSLock()
    private var inbound: [String: AggregatedEntry] = [:]
    private var drainScheduled = false
    private var pending: [String: AggregatedEntry] = [:]
    private var pendingOrder: [String] = []
    private var flushing = false
    private var flushPending = false
    private var shuttingDown = false
    private var timerPaused = false
    private var shutdownSemaphore: DispatchSemaphore?

    private final class AggregatedEntry {
        var aggregationKey: String
        var feature: FlagsSDKFeatureResult
        var displayCount: Int
        var lastEvaluatedAtMillis: Int64

        init(
            aggregationKey: String,
            feature: FlagsSDKFeatureResult,
            displayCount: Int,
            lastEvaluatedAtMillis: Int64
        ) {
            self.aggregationKey = aggregationKey
            self.feature = feature
            self.displayCount = displayCount
            self.lastEvaluatedAtMillis = lastEvaluatedAtMillis
        }
    }

    convenience init(flushCallback: @escaping ExposureFlushCallback) {
        let queue = DispatchQueue(label: "FlagExposure")
        self.init(
            flushCallback: flushCallback,
            workQueue: queue,
            flushTimer: ScheduledFlushTimer(queue: queue),
            flushIntervalMs: FlagConstants.ExposureQueue.flushIntervalMs,
            batchSize: FlagConstants.ExposureQueue.batchSize,
            executeOnCallerThread: false
        )
    }

    init(
        flushCallback: @escaping ExposureFlushCallback,
        workQueue: DispatchQueue,
        flushTimer: FlushTimer,
        flushIntervalMs: Int64,
        batchSize: Int,
        executeOnCallerThread: Bool
    ) {
        guard batchSize >= 1 else {
            fatalError("batchSize must be >= 1")
        }
        guard flushIntervalMs > 0 else {
            fatalError("flushIntervalMs must be > 0")
        }

        self.flushCallback = flushCallback
        self.workQueue = workQueue
        self.flushTimer = flushTimer
        self.flushIntervalMs = flushIntervalMs
        self.batchSize = batchSize
        self.executeOnCallerThread = executeOnCallerThread
    }

    func enqueue(aggregationKey: String, feature: FlagsSDKFeatureResult, evaluatedAtMillis: Int64) {
        guard !aggregationKey.isEmpty, !shuttingDown else {
            return
        }

        mergeInbound(aggregationKey: aggregationKey, feature: feature, evaluatedAtMillis: evaluatedAtMillis)
        scheduleDrain()
    }

    func flush() {
        guard !shuttingDown else {
            return
        }
        execute { [weak self] in
            self?.drainInboundToPending()
            self?.doFlush()
        }
    }

    func pausePeriodicFlush() {
        guard !shuttingDown else {
            return
        }
        execute { [weak self] in
            self?.timerPaused = true
            self?.flushTimer.cancel()
        }
    }

    func resumePeriodicFlush() {
        guard !shuttingDown else {
            return
        }
        execute { [weak self] in
            guard let self else {
                return
            }
            self.timerPaused = false
            self.drainInboundToPending()
            self.flushEventsIfRequired()
        }
    }

    func shutdown() {
        shuttingDown = true
        let semaphore = DispatchSemaphore(value: 0)
        shutdownSemaphore = semaphore
        execute { [weak self] in
            self?.doShutdown()
            semaphore.signal()
        }
    }

    func awaitShutdown(timeout: TimeInterval) -> Bool {
        guard let semaphore = shutdownSemaphore else {
            return true
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }

    // MARK: - Private

    private func execute(_ work: @escaping () -> Void) {
        if executeOnCallerThread {
            work()
        } else {
            workQueue.async(execute: work)
        }
    }

    private func mergeInbound(
        aggregationKey: String,
        feature: FlagsSDKFeatureResult,
        evaluatedAtMillis: Int64
    ) {
        inboundLock.lock()
        defer { inboundLock.unlock() }

        if let existing = inbound[aggregationKey] {
            existing.displayCount += 1
            existing.lastEvaluatedAtMillis = evaluatedAtMillis
            return
        }

        inbound[aggregationKey] = AggregatedEntry(
            aggregationKey: aggregationKey,
            feature: feature,
            displayCount: 1,
            lastEvaluatedAtMillis: evaluatedAtMillis
        )
    }

    private func scheduleDrain() {
        guard !shuttingDown else {
            return
        }

        inboundLock.lock()
        if drainScheduled {
            inboundLock.unlock()
            return
        }
        drainScheduled = true
        inboundLock.unlock()

        execute { [weak self] in
            self?.drainInbound()
        }
    }

    private func drainInbound() {
        defer {
            inboundLock.lock()
            drainScheduled = false
            let hasInbound = !inbound.isEmpty
            inboundLock.unlock()

            if !shuttingDown, hasInbound {
                scheduleDrain()
            }
        }

        guard !shuttingDown else {
            return
        }

        drainInboundToPending()
        flushEventsIfRequired()
    }

    private func drainInboundToPending() {
        inboundLock.lock()
        let keys = Array(inbound.keys)
        inboundLock.unlock()

        for key in keys {
            inboundLock.lock()
            let inboundEntry = inbound.removeValue(forKey: key)
            inboundLock.unlock()

            if let inboundEntry {
                mergeIntoPending(inboundEntry)
            }
        }
    }

    private func mergeIntoPending(_ inboundEntry: AggregatedEntry) {
        if let existing = pending[inboundEntry.aggregationKey] {
            existing.displayCount += inboundEntry.displayCount
            existing.lastEvaluatedAtMillis = inboundEntry.lastEvaluatedAtMillis
            return
        }

        pending[inboundEntry.aggregationKey] = inboundEntry
        pendingOrder.append(inboundEntry.aggregationKey)
    }

    private func flushEventsIfRequired() {
        guard !pending.isEmpty else {
            return
        }

        if pending.count >= batchSize {
            doFlush()
        } else if !flushing, !timerPaused, !flushTimer.isScheduled {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        guard !timerPaused, !shuttingDown, !pending.isEmpty else {
            return
        }

        flushTimer.schedule(delayMs: flushIntervalMs) { [weak self] in
            guard let self, !self.shuttingDown else {
                return
            }
            self.drainInboundToPending()
            self.doFlush()
        }
    }

    private func doFlush() {
        if flushing {
            flushPending = true
            return
        }

        guard !pending.isEmpty else {
            return
        }

        flushing = true
        flushTimer.cancel()
        defer { flushing = false }

        repeat {
            flushPending = false
            let batch = pendingOrder.compactMap { pending[$0] }
            pending.removeAll()
            pendingOrder.removeAll()

            let events = batch.map {
                AggregatedExposureEvent(
                    aggregationKey: $0.aggregationKey,
                    feature: $0.feature,
                    lastEvaluatedAtMillis: $0.lastEvaluatedAtMillis,
                    displayCount: $0.displayCount
                )
            }

            flushCallback(events)
        } while flushPending || !pending.isEmpty
    }

    private func doShutdown() {
        shuttingDown = true
        flushTimer.cancel()
        drainInboundToPending()
        doFlush()
    }
}

// MARK: - Flush timers

final class ScheduledFlushTimer: FeatureExposureQueue.FlushTimer {
    private let queue: DispatchQueue
    private var workItem: DispatchWorkItem?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var isScheduled: Bool {
        guard let workItem else { return false }
        return !workItem.isCancelled
    }

    func schedule(delayMs: Int64, task: @escaping () -> Void) {
        cancel()
        let item = DispatchWorkItem { [weak self] in
            task()
            self?.workItem = nil
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs)), execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

final class ManualFlushTimer: FeatureExposureQueue.FlushTimer {
    private var task: (() -> Void)?
    private(set) var delayMs: Int64 = 0

    var isScheduled: Bool {
        task != nil
    }

    func schedule(delayMs: Int64, task: @escaping () -> Void) {
        self.delayMs = delayMs
        self.task = task
    }

    func cancel() {
        task = nil
        delayMs = 0
    }

    func fire() {
        guard let runnable = task else {
            return
        }
        task = nil
        runnable()
    }
}

final class NoOpFlushTimer: FeatureExposureQueue.FlushTimer {
    var isScheduled: Bool { false }

    func schedule(delayMs: Int64, task: @escaping () -> Void) {}

    func cancel() {}
}
