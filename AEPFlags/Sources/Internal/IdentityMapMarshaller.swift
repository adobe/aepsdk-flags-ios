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

/// Converts Edge Identity data into the XDM identityMap shape required by `GetFeatureRequest`.
enum IdentityMapMarshaller {
    static let keyId = "id"
    static let keyPrimary = "primary"
    static let keyAuthenticatedState = "authenticatedState"

    /// Top-level key in Edge Identity XDM shared state.
    static let xdmKeyIdentityMap = "identityMap"

    private static let authenticatedStateAmbiguous = "ambiguous"

    /// Parses an XDM shared state map from `getXDMSharedState` into the `GetFeatureRequest` identity map shape.
    static func fromXDMStateMap(_ xdmStateValue: [String: Any]?) -> [String: [[String: Any]]]? {
        guard let xdmStateValue, !xdmStateValue.isEmpty else {
            return nil
        }

        guard let identityMapValue = xdmStateValue[xdmKeyIdentityMap] as? [String: Any] else {
            return nil
        }

        return parseNamespacesMap(identityMapValue)
    }

    private static func parseNamespacesMap(_ namespacesMap: [String: Any]) -> [String: [[String: Any]]]? {
        guard !namespacesMap.isEmpty else {
            return nil
        }

        var result: [String: [[String: Any]]] = [:]
        for (namespace, value) in namespacesMap {
            guard let rawItems = value as? [Any] else {
                continue
            }

            var parsedItems: [[String: Any]] = []
            parsedItems.reserveCapacity(rawItems.count)
            for rawItem in rawItems {
                guard let itemMap = rawItem as? [String: Any],
                      let entry = parseIdentityItem(itemMap) else {
                    continue
                }
                parsedItems.append(entry)
            }

            if !parsedItems.isEmpty {
                result[namespace] = parsedItems
            }
        }

        return result.isEmpty ? nil : result
    }

    private static func parseIdentityItem(_ itemMap: [String: Any]) -> [String: Any]? {
        guard let rawId = itemMap[keyId] else {
            return nil
        }

        let id = String(describing: rawId).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return nil
        }

        var entry: [String: Any] = [
            keyId: id,
            keyPrimary: (itemMap[keyPrimary] as? Bool) == true
        ]

        if let authState = itemMap[keyAuthenticatedState] as? String, !authState.isEmpty {
            entry[keyAuthenticatedState] = authState
        } else {
            entry[keyAuthenticatedState] = authenticatedStateAmbiguous
        }

        return entry
    }
}
