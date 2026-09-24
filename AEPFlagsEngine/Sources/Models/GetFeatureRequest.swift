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

/// Request parameters for `Flag.getFeatures(for:)` / `Flag.getFeature(named:for:)`.
/// Immutable; build via the nested `Builder`.
@objc(AEPMobileGetFeatureRequest)
public final class GetFeatureRequest: NSObject {

    /// Shared empty request — no context, no identity map. Safe to reuse.
    @objc public static let defaultRequest: GetFeatureRequest = Builder().build()

    /// Targeting context (key → list of values).
    @objc public let context: [String: [String]]
    /// Identity map for A/B bucketing (namespace → identity entries).
    public let identityMap: [String: [[String: Any]]]

    /// Objective-C view of ``identityMap``.
    @objc public var identityMapEntries: NSDictionary {
        var outer: [String: [[String: Any]]] = [:]
        for (namespace, entries) in identityMap {
            outer[namespace] = entries
        }
        return outer as NSDictionary
    }

    fileprivate init(context: [String: [String]], identityMap: [String: [[String: Any]]]) {
        self.context = context
        self.identityMap = identityMap
        super.init()
    }

    /// Convenience factory for a fresh `Builder`.
    @objc public static func builder() -> Builder {
        return Builder()
    }

    @objc(AEPMobileGetFeatureRequestBuilder)
    public final class Builder: NSObject {

        private var _context: [String: [String]] = [:]
        private var _identityMap: [String: [[String: Any]]]?

        @objc public override init() {
            super.init()
        }

        /// Set the targeting context. Values are deep-copied at `build()`.
        @discardableResult
        @objc public func context(_ context: [String: [String]]) -> Builder {
            self._context = context
            return self
        }

        /// Set the identity map for A/B bucketing.
        /// Each namespace maps to a list of identity entries. Each entry must include
        /// `id` (String), `primary` (boolean), and `authenticatedState` (String).
        @discardableResult
        public func identityMap(_ identityMap: [String: [[String: Any]]]?) -> Builder {
            self._identityMap = identityMap
            return self
        }

        /// Objective-C entry point for identity map construction.
        @discardableResult
        @objc(identityMapEntries:)
        public func setIdentityMapEntries(_ entries: [String: [NSDictionary]]) -> Builder {
            var converted: [String: [[String: Any]]] = [:]
            for (namespace, list) in entries {
                converted[namespace] = list.map { $0 as? [String: Any] ?? [:] }
            }
            self._identityMap = converted
            return self
        }

        /// Build the immutable request.
        @objc public func build() -> GetFeatureRequest {
            return GetFeatureRequest(
                context: Self.copyContext(_context),
                identityMap: Self.copyIdentityMap(_identityMap)
            )
        }

        private static func copyContext(_ source: [String: [String]]) -> [String: [String]] {
            var copy: [String: [String]] = [:]
            copy.reserveCapacity(source.count)
            for (key, values) in source {
                copy[key] = Array(values)
            }
            return copy
        }

        private static func copyIdentityMap(_ source: [String: [[String: Any]]]?) -> [String: [[String: Any]]] {
            guard let source = source else { return [:] }
            var copy: [String: [[String: Any]]] = [:]
            copy.reserveCapacity(source.count)
            for (namespace, entries) in source {
                guard !entries.isEmpty else { continue }
                var copiedEntries: [[String: Any]] = []
                copiedEntries.reserveCapacity(entries.count)
                for entry in entries {
                    copiedEntries.append(entry)
                }
                if !copiedEntries.isEmpty {
                    copy[namespace] = copiedEntries
                }
            }
            return copy
        }
    }
}
