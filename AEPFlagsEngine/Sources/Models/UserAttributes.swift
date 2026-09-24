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

/// Container for caller-supplied user attributes used in rule evaluation.
/// Supports single-valued and multi-valued attributes.
@objc(AEPMobileUserAttributes)
public final class UserAttributes: NSObject {

    private var storage: [String: [String]]

    @objc public override init() {
        self.storage = [:]
        super.init()
    }

    /// Initialize from a `[key: [String]]` map (single-element lists are kept as single-valued).
    @objc public init(initialAttributes: [String: Any]) {
        var s: [String: [String]] = [:]
        for (key, value) in initialAttributes {
            Self.assignValue(value, forKey: key, into: &s)
        }
        self.storage = s
        super.init()
    }

    /// Build a `UserAttributes` from a `GetFeatureRequest`-style context map.
    @objc public static func from(context: [String: [String]]?) -> UserAttributes {
        let attrs = UserAttributes()
        guard let context = context else { return attrs }
        for (key, values) in context where !values.isEmpty {
            attrs.storage[key] = values
        }
        return attrs
    }

    // MARK: - Accessors

    /// All attributes as a `[key: [String]]` map. Returns all attributes as a map.
    @objc public var attributes: [String: [String]] { storage }

    /// First value for `key`, or `nil` if missing / empty.
    @objc public func attribute(forKey key: String) -> String? {
        return storage[key]?.first
    }

    /// All values for `key`, or `nil` if missing.
    @objc public func attributeValues(forKey key: String) -> [String]? {
        return storage[key]
    }

    /// `true` if an attribute with `key` exists.
    @objc public func hasAttribute(forKey key: String) -> Bool {
        return storage[key] != nil
    }

    // MARK: - Mutation (chainable)

    /// Add or update a single value.
    @discardableResult
    @objc public func addAttribute(_ value: Any, forKey key: String) -> UserAttributes {
        Self.assignValue(value, forKey: key, into: &storage)
        return self
    }

    /// Add or update a list of values.
    @discardableResult
    @objc public func addAttribute(values: [String], forKey key: String) -> UserAttributes {
        storage[key] = values
        return self
    }

    /// Remove an attribute by key.
    @discardableResult
    @objc public func removeAttribute(forKey key: String) -> UserAttributes {
        storage.removeValue(forKey: key)
        return self
    }

    /// Clear all attributes.
    @discardableResult
    @objc public func clear() -> UserAttributes {
        storage.removeAll(keepingCapacity: true)
        return self
    }

    /// Merge attributes from another `UserAttributes` instance. Overwrites on collision.
    @discardableResult
    @objc public func addOrUpdate(from other: UserAttributes?) -> UserAttributes {
        guard let other = other else { return self }
        for (key, values) in other.storage {
            storage[key] = values
        }
        return self
    }

    /// Shallow copy. Named `cloned()` to avoid colliding with `NSObject.copy()`.
    @objc(clonedAttributes)
    public func cloned() -> UserAttributes {
        let result = UserAttributes()
        result.storage = storage
        return result
    }

    // MARK: - Helpers

    private static func assignValue(_ value: Any,
                                    forKey key: String,
                                    into storage: inout [String: [String]]) {
        if let list = value as? [Any] {
            storage[key] = list.map { String(describing: $0) }
        } else {
            storage[key] = [String(describing: value)]
        }
    }
}
