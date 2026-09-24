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

enum FlagConstants {
    static let logTag = "Flags"
    static let extensionVersion = "1.0.0"
    static let extensionName = "com.adobe.flags"
    static let friendlyName = "Flags"
    static let apiTimeoutSeconds: TimeInterval = 10.0

    enum EventNames {
        static let getFeatureRequest = "Flags Get Feature Request"
        static let isFeatureEnabledRequest = "Flags Is Feature Enabled Request"
        static let flagsResponse = "Flags Response"
        static let edgeFeatureExposureRequest = "Flags Edge Feature Exposure"
    }

    enum EventType {
        static let flags = "com.adobe.eventType.flags"
    }

    enum EventSource {
        static let requestContent = "com.adobe.eventSource.requestContent"
        static let responseContent = "com.adobe.eventSource.responseContent"
        static let requestReset = "com.adobe.eventSource.requestReset"
    }

    enum EventDataKeys {
        static let requestType = "requesttype"
        static let featureName = "featurename"
        static let context = "context"
        static let feature = "feature"
        static let id = "id"
        static let key = "key"
        static let featureGroupKey = "featureGroupKey"
        static let meta = "meta"
        static let analyticsParam = "analyticsParam"
        static let featureGroupId = "featureGroupId"
        static let featureId = "featureId"
        static let variantId = "variantId"
        static let isEnabled = "isenabled"
        static let responseError = "responseerror"
    }

    enum EventDataValues {
        static let requestTypeGetFeature = "getfeature"
        static let requestTypeIsEnabled = "isfeatureenabled"
    }

    enum Edge {
        static let xdm = "xdm"
        static let data = "data"
        static let eventType = "eventType"
        static let eventTypePropositionDisplay = "decisioning.propositionDisplay"
        static let timestamp = "timestamp"
        static let identityMap = "identityMap"
        static let identityId = "id"
        static let identityPrimary = "primary"
        static let experience = "_experience"
        static let decisioning = "decisioning"
        static let propositionEventType = "propositionEventType"
        static let display = "display"
        static let propositions = "propositions"
        static let scopeDetails = "scopeDetails"
        static let decisionProvider = "decisionProvider"
        static let decisionProviderFlags = "FLAGS"
        static let correlationId = "correlationID"
        static let correlationIdSeparator = "-"
        static let activity = "activity"
        static let scopeExperience = "experience"
        static let strategies = "strategies"
        static let algorithmId = "algorithmID"
        static let algorithmMurmur = "murmur"
        static let characteristics = "characteristics"
        static let entityType = "entityType"
        static let entityTypeFeature = "feature"
        static let entityTypeFeatureGroup = "featureGroup"
        static let items = "items"
        static let name = "name"
        static let variantPrefix = "Variant-"
        static let featureActivityPrefix = "F-"
        static let featureGroupActivityPrefix = "FG-"
        static let standaloneFeaturesFeatureGroupKey = "||features||"
        static let standaloneFeaturesFeatureGroupId = -1

        /// Keys for AEPEdge request property overrides (`EdgeConstants.EventDataKeys.Request` in aepsdk-edge-ios).
        /// The `request` object is consumed by AEPEdge when building the network URL and is not sent in the event payload body.
        enum Request {
            static let key = "request"
            static let path = "path"
            /// Collect endpoint path segment for non-interactive analytics (`POST …/ee/v1/collect`).
            /// https://developer.adobe.com/data-collection-apis/docs/endpoints/collect/
            static let collectPath = "/v1/collect"
        }
    }

    enum ExposureQueue {
        static let batchSize = 20
        static let flushIntervalMs: Int64 = 150_000
    }

    enum Configuration {
        static let extensionName = "com.adobe.module.configuration"
        static let edgeDomain = "edge.domain"
        static let defaultEdgeDomain = "edge.adobedc.net"
        static let flagsClientId = "flags.clientId"
        static let flagsSandbox = "flags.sandbox"
        static let experienceCloudOrg = "experienceCloud.org"
    }

    enum EdgeIdentity {
        static let extensionName = "com.adobe.edge.identity"
    }

    enum Lifecycle {
        static let actionKey = "action"
        static let actionStart = "start"
        static let actionPause = "pause"
    }

    /// Keys/values published in the Flag extension shared state (`extensionName`), used by `readyForEvent`
    /// to signal Flags Mobile client readiness to Mobile Core EventHub.
    enum SharedState {
        static let initializationStatus = "initializationStatus"
        static let statusReady = "ready"
        static let statusFailed = "failed"
    }
}
