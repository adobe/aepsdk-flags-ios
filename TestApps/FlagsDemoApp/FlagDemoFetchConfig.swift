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

/// Defaults for Flags demo evaluation. Populate locally before running against a real environment.
enum FlagDemoFetchConfig {
    static let logTag = ""

    /// Launch environment ID (Data Collection UI). Set locally before running the demo.
    static let launchAppId = ""

    static let ecidNamespace = ""
    static let ecidValue = ""

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

    /// Example feature flags with friendly names, mirroring the Luma Flags reference app.
    /// Replace these keys with the flags provisioned in your own environment.
    static let knownFeatures: [FeatureInfo] = [
        FeatureInfo(key: "ai-assistant", displayName: "AI Assistant", description: "Example flag: AI assistant entry point"),
        FeatureInfo(key: "premium-support", displayName: "Premium Support", description: "Example flag: premium support card"),
        FeatureInfo(key: "loyalty-rewards", displayName: "Loyalty Rewards", description: "Example flag: loyalty & rewards"),
        FeatureInfo(key: "store-locator", displayName: "Store Locator", description: "Example flag: store locator tab"),
        FeatureInfo(key: "featured-products", displayName: "Featured Products", description: "Example flag: featured carousel"),
        FeatureInfo(key: "personalization-hub", displayName: "Personalization Hub", description: "Example flag: personalization/offers"),
        FeatureInfo(key: "push-promotions", displayName: "Push Promotions", description: "Example flag: promo notifications"),
        FeatureInfo(key: "member-login-badge", displayName: "Member Login Badge", description: "Example flag: member login badge")
    ]

    /// Feature keys provisioned in your environment. Defaults to the known example keys.
    static var provisionFeatureKeys: [String] { knownFeatures.map(\.key) }

    static let defaultFeatureKey = "ai-assistant"

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

    /// Builds an evaluation context, optionally injecting a custom identity entry
    /// (namespace + id) alongside the editable attributes.
    static func buildEvaluationContext(
        from entries: [ContextEntry],
        customIdentityNamespace: String?,
        customIdentityId: String?
    ) -> FeatureEvaluationContext {
        var attributes = mergedAttributes(from: entries)
        if let namespace = customIdentityNamespace, !namespace.isEmpty,
           let id = customIdentityId, !id.isEmpty {
            attributes[namespace] = [id]
        }
        return FeatureEvaluationContext.builder()
            .withAttributes(attributes)
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
