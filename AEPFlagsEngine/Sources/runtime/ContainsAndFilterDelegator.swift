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

/// Delegator for the `CONTAINS` operator when its right-hand side is a nested
/// `FILTER` type. Walks each `UserAttributes` entry in the state and evaluates
/// the inner filter against it.
final class ContainsAndFilterDelegator: FilterValidatorDelegator {

    private static let selectedAttrPrefix = "selected_"
    private static let defaultFilterId = 0

    private let filterService: FilterService

    init(filterService: FilterService) {
        self.filterService = filterService
    }

    // MARK: - FilterValidatorDelegator

    func delegate(stateValue: Any?, filterValue: Any?, relationalEquality: Any?) -> Bool {
        let filter = filter(from: filterValue)
        guard let states = stateValue as? [Any] else { return false }
        for state in states {
            if let attrs = toUserAttributes(state), filterService.isValid(attrs, filter: filter) {
                return true
            }
        }
        return false
    }

    func delegateWithReturnValues(stateValue: Any?,
                                  filterValue: Any?,
                                  relationalEquality: Any?,
                                  id: Int,
                                  attrId: String?) -> FilterResult {
        let filter = filter(from: filterValue)
        guard let states = stateValue as? [Any] else {
            return FilterResult(isValid: false, matchedAttributes: UserAttributes())
        }

        for state in states {
            if let attrs = toUserAttributes(state), filterService.isValid(attrs, filter: filter) {
                return FilterResult(isValid: true,
                                    matchedAttributes: generateReturnValues(id: id, from: attrs))
            }
        }
        // No match — surface the first state's keys with `false`.
        if let first = states.first, let attrs = toUserAttributes(first) {
            return FilterResult(isValid: false,
                                matchedAttributes: generateReturnValues(id: id, from: attrs))
        }
        return FilterResult(isValid: false, matchedAttributes: UserAttributes())
    }

    func delegateWithAllReturnValues(stateValue: Any?,
                                     filterValue: Any?,
                                     relationalEquality: Any?,
                                     id: Int,
                                     attrId: String?) -> [UserAttributes] {
        let filter = filter(from: filterValue)
        guard let states = stateValue as? [Any] else { return [] }
        var valid: [UserAttributes] = []
        for state in states {
            if let attrs = toUserAttributes(state), filterService.isValid(attrs, filter: filter) {
                valid.append(attrs)
            }
        }
        return valid
    }

    func preprocessUserAttributes(stateValue: Any?, objectToValidate: UserAttributes) {
        guard let states = stateValue as? [Any] else { return }
        let selected = selectedAttributes(from: objectToValidate)
        for state in states {
            (state as? UserAttributes)?.addOrUpdate(from: selected)
        }
    }

    // MARK: - Helpers

    private func filter(from value: Any?) -> IFilter {
        if value == nil { return EmptyFilter() }
        if let filter = value as? IFilter { return filter }
        return filterService.filter(fromMap: value)
    }

    private func toUserAttributes(_ object: Any) -> UserAttributes? {
        if let attrs = object as? UserAttributes { return attrs }
        if let map = object as? [String: Any] { return mapToUserAttributes(map) }
        return nil
    }

    private func mapToUserAttributes(_ map: [String: Any]) -> UserAttributes {
        let attrs = UserAttributes()
        for (key, value) in map {
            attrs.addAttribute(value, forKey: key)
        }
        return attrs
    }

    private func generateReturnValues(id: Int, from selected: UserAttributes) -> UserAttributes {
        let result = UserAttributes()
        if id == Self.defaultFilterId { return result }
        for (key, values) in selected.attributes {
            if key.hasPrefix(Self.selectedAttrPrefix) { continue }
            if values.isEmpty { continue }
            result.addAttribute(values: values, forKey: "matched_\(id)_\(key)")
        }
        return result
    }

    private func selectedAttributes(from user: UserAttributes) -> UserAttributes {
        let selected = UserAttributes()
        for (key, values) in user.attributes where key.hasPrefix(Self.selectedAttrPrefix) {
            selected.addAttribute(values: values, forKey: key)
        }
        return selected
    }
}
