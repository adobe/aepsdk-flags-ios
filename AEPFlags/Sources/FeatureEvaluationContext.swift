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

/// Immutable evaluation context for Flag feature flag APIs.
@objc(AEPFeatureEvaluationContext)
public final class FeatureEvaluationContext: NSObject {
    private let attributesValue: [String: [String]]?

    private init(attributes: [String: [String]]?) {
        attributesValue = attributes
        super.init()
    }

    @objc public static func builder() -> Builder {
        Builder()
    }

    @objc public var attributes: [String: [String]]? {
        attributesValue
    }

    private static func freeze(_ source: [String: [String]]?) -> [String: [String]]? {
        guard let source, !source.isEmpty else {
            return nil
        }
        var out: [String: [String]] = [:]
        for (key, values) in source {
            out[key] = Array(values)
        }
        return out
    }

    @objc(AEPFeatureEvaluationContextBuilder)
    public final class Builder: NSObject {
        private var attributes: [String: [String]]?
        private var attributesSet = false

        @objc public func withAttributes(_ attributes: [String: [String]]?) -> Builder {
            if attributesSet {
                NSException(
                    name: .invalidArgumentException,
                    reason: "Attributes already set on this builder. Mixing is not allowed.",
                    userInfo: nil
                ).raise()
            }
            attributesSet = true
            self.attributes = attributes
            return self
        }

        @objc public func build() -> FeatureEvaluationContext {
            FeatureEvaluationContext(attributes: FeatureEvaluationContext.freeze(attributes))
        }
    }
}
