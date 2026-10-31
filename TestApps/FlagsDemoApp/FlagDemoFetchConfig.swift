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

import AEPFlags
import Foundation

/// Settings for the Flags demo. Set these locally before you run the demo against your own mobile property.
enum FlagDemoFetchConfig {
    static let logTag = ""

    /// Environment File ID of your mobile property. In Data Collection, open your mobile property and
    /// select Environments to find it. While this is empty, the demo shows a message and doesn't configure the SDK.
    static let environmentFileId = ""

    /// Configuration keys published from Data Collection for the Flags extension.
    /// Used by the runtime config-override panel (dev/testing only).
    enum ConfigKeys {
        static let clientId = "flags.clientId"
        static let sandbox = "flags.sandbox"
        static let imsOrg = "experienceCloud.org"
        static let edgeDomain = "edge.domain"
    }

    /// Default evaluation attributes sent with each flag evaluation request.
    /// Edit here or via the demo's Evaluation Context editor.
    static let baseAttributes: [String: [String]] = [
        "appVersion": ["6.0.0"],
        "locale": ["en_US"],
        "platform": ["iOS"]
    ]

    static var defaultContextEntries: [ContextEntry] {
        // Stable, readable order for the editor rows.
        baseAttributes
            .sorted { $0.key < $1.key }
            .map { (key, values) in ContextEntry(key: key, value: values.first ?? "") }
    }

    /// Feature flags that the Flags tab evaluates. Empty by default: add the feature keys you created in
    /// Experience Flags. While this list is empty, the demo shows a message instead of evaluating flags.
    ///
    /// Example:
    /// `FeatureInfo(key: "new-checkout", displayName: "New Checkout", description: "New checkout flow")`
    static let knownFeatures: [FeatureInfo] = []

    /// Feature keys offered by the key picker on the Get Feature tab.
    static var featureKeys: [String] { knownFeatures.map(\.key) }

    /// Initial feature key on the Get Feature tab. Empty when `knownFeatures` is empty.
    static var defaultFeatureKey: String { knownFeatures.first?.key ?? "" }

    static func mergedAttributes(from entries: [ContextEntry]) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for entry in entries where !entry.key.isEmpty {
            out[entry.key] = [entry.value]
        }
        return out
    }

    static func buildEvaluationContext(from entries: [ContextEntry]) -> FeatureEvaluationContext {
        FeatureEvaluationContext.builder()
            .withAttributes(mergedAttributes(from: entries))
            .build()
    }
}

struct FeatureInfo: Identifiable {
    var id: String { key }
    let key: String
    let displayName: String
    let description: String
}

struct FeatureState: Identifiable {
    var id: String { key }
    let key: String
    let enabled: Bool
    let info: FeatureInfo
    let evaluationError: String?
}

struct ContextEntry: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}
