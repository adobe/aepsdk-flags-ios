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

/// Generates exposure event identifiers for the batched exposure pipeline.
enum ExposureEventIdGenerator {
    static func generateAggregationKey(_ feature: FlagsSDKFeatureResult?) -> String? {
        guard let feature, let analytics = feature.analyticsParam, let variantId = analytics.variantId else {
            return nil
        }

        if isStandaloneFeature(feature) {
            return formatCorrelationId(
                FlagConstants.Edge.featureActivityPrefix + String(analytics.featureId),
                variantId
            )
        }

        return formatFeatureGroupAggregationKey(
            featureGroupId: analytics.featureGroupId,
            featureId: analytics.featureId,
            variantId: variantId
        )
    }

    static func generateCorrelationId(_ feature: FlagsSDKFeatureResult?) -> String? {
        guard let feature, let analytics = feature.analyticsParam, let variantId = analytics.variantId else {
            return nil
        }

        let activityId = resolveCorrelationActivityId(feature)
        return formatCorrelationId(activityId, variantId)
    }

    static func isExposureEligible(_ feature: FlagsSDKFeatureResult?) -> Bool {
        guard let feature, let analytics = feature.analyticsParam else {
            return false
        }
        return analytics.variantId != nil
    }

    static func isStandaloneFeature(_ feature: FlagsSDKFeatureResult) -> Bool {
        guard let analytics = feature.analyticsParam else {
            return false
        }
        return analytics.featureGroupId == FlagConstants.Edge.standaloneFeaturesFeatureGroupId
            || feature.featureGroupKey == FlagConstants.Edge.standaloneFeaturesFeatureGroupKey
    }

    static func formatCorrelationId(_ activityId: String, _ variantId: String) -> String {
        activityId + FlagConstants.Edge.correlationIdSeparator + variantId
    }

    static func resolveCorrelationActivityId(_ feature: FlagsSDKFeatureResult) -> String {
        let analytics = feature.analyticsParam!
        if isStandaloneFeature(feature) {
            return FlagConstants.Edge.featureActivityPrefix + String(analytics.featureId)
        }
        return FlagConstants.Edge.featureGroupActivityPrefix + String(analytics.featureGroupId)
    }

    private static func formatFeatureGroupAggregationKey(
        featureGroupId: Int,
        featureId: Int,
        variantId: String
    ) -> String {
        FlagConstants.Edge.featureGroupActivityPrefix
            + String(featureGroupId)
            + FlagConstants.Edge.correlationIdSeparator
            + String(featureId)
            + FlagConstants.Edge.correlationIdSeparator
            + variantId
    }
}
