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

@objc public extension Flag {
    private static let selfTag = "Flag"

  /// Returns the installed version of the Flag extension.
    @objc(flagExtensionVersion)
    static func flagExtensionVersion() -> String {
        FlagConstants.extensionVersion
    }

  /// Evaluates a feature for the given key and returns the full evaluation result when a match exists.
    @objc(getFeature:evaluationContext:completion:)
    static func getFeature(
        _ featureKey: String,
        evaluationContext: FeatureEvaluationContext,
        completion: @escaping (FeatureEvaluationResult?) -> Void
    ) {
        getFeature(featureKey, evaluationContext: evaluationContext, completion: completion, errorCallback: nil)
    }

  /// Evaluates a feature with an optional error callback.
    @objc(getFeature:evaluationContext:completion:errorCallback:)
    static func getFeature(
        _ featureKey: String,
        evaluationContext: FeatureEvaluationContext,
        completion: @escaping (FeatureEvaluationResult?) -> Void,
        errorCallback: ((AEPError) -> Void)?
    ) {
        dispatchGetFeatureRequest(
            featureKey: featureKey,
            context: evaluationContext.attributes,
            completion: completion,
            errorCallback: errorCallback
        )
    }

  /// Evaluates whether a feature is enabled for the given key and evaluation context.
    @objc(isFeatureEnabled:evaluationContext:completion:)
    static func isFeatureEnabled(
        _ featureKey: String,
        evaluationContext: FeatureEvaluationContext,
        completion: @escaping (Bool) -> Void
    ) {
        isFeatureEnabled(featureKey, evaluationContext: evaluationContext, completion: completion, errorCallback: nil)
    }

  /// Evaluates whether a feature is enabled with an optional error callback.
    @objc(isFeatureEnabled:evaluationContext:completion:errorCallback:)
    static func isFeatureEnabled(
        _ featureKey: String,
        evaluationContext: FeatureEvaluationContext,
        completion: @escaping (Bool) -> Void,
        errorCallback: ((AEPError) -> Void)?
    ) {
        dispatchIsFeatureEnabledRequest(
            featureKey: featureKey,
            context: evaluationContext.attributes,
            completion: completion,
            errorCallback: errorCallback
        )
    }

    // MARK: - Private

    private static func dispatchGetFeatureRequest(
        featureKey: String,
        context: [String: [String]]?,
        completion: @escaping (FeatureEvaluationResult?) -> Void,
        errorCallback: ((AEPError) -> Void)?
    ) {
        if featureKey.isEmpty {
            Log.warning(label: FlagConstants.logTag, "\(selfTag) - Cannot get feature, feature key is empty.")
            failWithError(errorCallback: errorCallback, error: .unexpected)
            return
        }

        var eventData: [String: Any] = [
            FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeGetFeature,
            FlagConstants.EventDataKeys.featureName: featureKey
        ]
        if let context {
            eventData[FlagConstants.EventDataKeys.context] = context
        }

        let event = Event(
            name: FlagConstants.EventNames.getFeatureRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: eventData
        )

        MobileCore.dispatch(event: event, timeout: FlagConstants.apiTimeoutSeconds) { responseEvent in
            guard let responseEvent else {
                failWithError(errorCallback: errorCallback, error: .callbackTimeout)
                return
            }

            guard let responseData = responseEvent.data, !responseData.isEmpty else {
                failWithError(errorCallback: errorCallback, error: .unexpected)
                return
            }

            if responseData[FlagConstants.EventDataKeys.responseError] != nil {
                failWithError(errorCallback: errorCallback, error: responseEvent.flagResponseError ?? .unexpected)
                return
            }

            let featureMap = responseData[FlagConstants.EventDataKeys.feature] as? [String: Any]
            do {
                if let featureMap {
                    if let result = try FlagResponseMapper.toFeatureEvaluationResult(featureMap) {
                        completion(result)
                    } else {
                        completion(nil)
                    }
                } else {
                    completion(nil)
                }
            } catch {
                failWithError(errorCallback: errorCallback, error: .unexpected)
            }
        }
    }

    private static func dispatchIsFeatureEnabledRequest(
        featureKey: String,
        context: [String: [String]]?,
        completion: @escaping (Bool) -> Void,
        errorCallback: ((AEPError) -> Void)?
    ) {
        if featureKey.isEmpty {
            Log.warning(label: FlagConstants.logTag, "\(selfTag) - Cannot check feature enabled, feature key is empty.")
            failWithError(errorCallback: errorCallback, error: .unexpected)
            return
        }

        var eventData: [String: Any] = [
            FlagConstants.EventDataKeys.requestType: FlagConstants.EventDataValues.requestTypeIsEnabled,
            FlagConstants.EventDataKeys.featureName: featureKey
        ]
        if let context {
            eventData[FlagConstants.EventDataKeys.context] = context
        }

        let event = Event(
            name: FlagConstants.EventNames.isFeatureEnabledRequest,
            type: FlagConstants.EventType.flags,
            source: FlagConstants.EventSource.requestContent,
            data: eventData
        )

        MobileCore.dispatch(event: event, timeout: FlagConstants.apiTimeoutSeconds) { responseEvent in
            guard let responseEvent else {
                failWithError(errorCallback: errorCallback, error: .callbackTimeout)
                return
            }

            guard let responseData = responseEvent.data, !responseData.isEmpty else {
                failWithError(errorCallback: errorCallback, error: .unexpected)
                return
            }

            if responseData[FlagConstants.EventDataKeys.responseError] != nil {
                failWithError(errorCallback: errorCallback, error: responseEvent.flagResponseError ?? .unexpected)
                return
            }

            let isEnabled = FlagDataReader.optBool(responseData, key: FlagConstants.EventDataKeys.isEnabled, defaultValue: false)
            completion(isEnabled)
        }
    }

    private static func failWithError(errorCallback: ((AEPError) -> Void)?, error: AEPError) {
        errorCallback?(error)
    }
}
