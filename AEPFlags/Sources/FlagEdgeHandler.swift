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

/// Builds and dispatches feature evaluation exposure events to Edge.
enum FlagEdgeHandler {
    private static let selfTag = "FlagEdgeHandler"
    private static let zeroMillisUtcSuffixLength = 5

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func dispatchExposureEvents(
        extensionRuntime: ExtensionRuntime,
        events: [AggregatedExposureEvent]
    ) {
        for event in events {
            do {
                try dispatchExposureEvent(extensionRuntime: extensionRuntime, event: event)
            } catch {
                Log.warning(
                    label: FlagConstants.logTag,
                    "\(selfTag) - Failed to dispatch aggregated exposure event for aggregationKey=\(event.aggregationKey): \(error.localizedDescription)"
                )
            }
        }
    }

    static func dispatchExposureEvent(
        extensionRuntime: ExtensionRuntime,
        event: AggregatedExposureEvent
    ) throws {
        guard ExposureEventIdGenerator.isExposureEligible(event.feature), event.displayCount > 0 else {
            return
        }

        let xdm = buildDecisioningXdm(feature: event.feature, displayCount: event.displayCount)
        try dispatchEdgeEvent(extensionRuntime: extensionRuntime, xdm: xdm, evaluatedAtMillis: event.lastEvaluatedAtMillis)
    }

    private static func buildDecisioningXdm(feature: FlagsSDKFeatureResult, displayCount: Int) -> [String: Any] {
        let scopeDetails = buildScopeDetails(feature: feature)

        var proposition: [String: Any] = [
            FlagConstants.Edge.scopeDetails: scopeDetails
        ]
        if !ExposureEventIdGenerator.isStandaloneFeature(feature) {
            proposition[FlagConstants.Edge.items] = buildFeatureGroupItems(feature: feature)
        }

        let decisioning: [String: Any] = [
            FlagConstants.Edge.propositionEventType: [FlagConstants.Edge.display: displayCount],
            FlagConstants.Edge.propositions: [proposition]
        ]

        return [
            FlagConstants.Edge.eventType: FlagConstants.Edge.eventTypePropositionDisplay,
            FlagConstants.Edge.experience: [FlagConstants.Edge.decisioning: decisioning]
        ]
    }

    private static func buildScopeDetails(feature: FlagsSDKFeatureResult) -> [String: Any] {
        let analytics = feature.analyticsParam!
        let standalone = ExposureEventIdGenerator.isStandaloneFeature(feature)
        let variantId = analytics.variantId ?? ""

        let activityId = ExposureEventIdGenerator.resolveCorrelationActivityId(feature)
        let activityName = standalone ? analytics.featureKey : (feature.featureGroupKey ?? "")
        let entityType = standalone
            ? FlagConstants.Edge.entityTypeFeature
            : FlagConstants.Edge.entityTypeFeatureGroup

        return [
            FlagConstants.Edge.decisionProvider: FlagConstants.Edge.decisionProviderFlags,
            FlagConstants.Edge.correlationId: ExposureEventIdGenerator.formatCorrelationId(activityId, variantId),
            FlagConstants.Edge.activity: [
                FlagConstants.Edge.identityId: activityId,
                FlagConstants.Edge.name: activityName
            ],
            FlagConstants.Edge.scopeExperience: [
                FlagConstants.Edge.identityId: FlagConstants.Edge.variantPrefix + variantId
            ],
            FlagConstants.Edge.strategies: [[FlagConstants.Edge.algorithmId: FlagConstants.Edge.algorithmMurmur]],
            FlagConstants.Edge.characteristics: [FlagConstants.Edge.entityType: entityType]
        ]
    }

    private static func buildFeatureGroupItems(feature: FlagsSDKFeatureResult) -> [[String: Any]] {
        let analytics = feature.analyticsParam!
        return [[
            FlagConstants.Edge.identityId: String(analytics.featureId),
            FlagConstants.Edge.name: analytics.featureKey
        ]]
    }

    private static func formatTimestamp(_ evaluatedAtMillis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(evaluatedAtMillis) / 1000.0)
        var formatted = iso8601Formatter.string(from: date)
        if formatted.hasSuffix(".000Z") {
            formatted = String(formatted.dropLast(zeroMillisUtcSuffixLength)) + "Z"
        }
        return formatted
    }

    private static func buildEdgeEventData(xdm: [String: Any], evaluatedAtMillis: Int64?) -> [String: Any] {
        var xdmPayload = xdm
        if let evaluatedAtMillis {
            xdmPayload[FlagConstants.Edge.timestamp] = formatTimestamp(evaluatedAtMillis)
        }

        return [
            FlagConstants.Edge.xdm: xdmPayload,
            FlagConstants.Edge.Request.key: [
                FlagConstants.Edge.Request.path: FlagConstants.Edge.Request.collectPath
            ]
        ]
    }

    private static func dispatchEdgeEvent(
        extensionRuntime: ExtensionRuntime,
        xdm: [String: Any],
        evaluatedAtMillis: Int64?
    ) throws {
        let eventData = buildEdgeEventData(xdm: xdm, evaluatedAtMillis: evaluatedAtMillis)

        let edgeEvent = Event(
            name: FlagConstants.EventNames.edgeFeatureExposureRequest,
            type: EventType.edge,
            source: EventSource.requestContent,
            data: eventData
        )

        if let override = extensionRuntime as? FlagExposureEdgeDispatchingOverride {
            try override.dispatchExposureEdgeEventOverride(edgeEvent)
        } else {
            extensionRuntime.dispatch(event: edgeEvent)
        }
    }
}
