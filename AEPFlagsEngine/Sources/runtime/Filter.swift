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

/// Leaf filter — a single `key COMPARATOR value` predicate evaluated against
/// `UserAttributes`.
final class Filter: IFilter {

    let key: String
    private(set) var value: Any?
    let comparator: FilterComparator
    let dataType: FieldDataType
    let id: Int
    let isExpression: Bool
    let isSelectedVal: Bool
    let isPatch: Bool

    private let filterPatchesCache: FilterPatchesCache

    init(key: String,
         value: Any?,
         comparator: FilterComparator,
         dataType: FieldDataType?,
         id: Int = 0,
         isExpression: Bool = false,
         isSelectedVal: Bool = false) {
        self.key = key
        self.value = value
        self.comparator = comparator
        self.dataType = dataType ?? .string
        self.id = id
        self.isExpression = isExpression
        self.isSelectedVal = isSelectedVal
        self.isPatch = (comparator == .patch)
        self.filterPatchesCache = FilterPatchesCache.shared
    }

    /// Mutate the filter value — used by the tree generator when an expression is
    /// resolved once and cached on the filter.
    func setValue(_ value: Any?) {
        self.value = value
    }

    // MARK: - IFilter

    func isValid(_ userAttributes: UserAttributes) -> Bool {
        return validateWithReturnValues(userAttributes).isValid
    }

    func validateWithReturnValues(_ userAttributes: UserAttributes) -> FilterResult {
        // PATCH operator — delegate to a cached, pre-built filter.
        if isPatch {
            let patchKey = stringify(value)
            return filterPatchesCache.patch(for: patchKey).validateWithReturnValues(userAttributes)
        }

        // EXISTS — boolean check against attribute presence.
        if comparator == .ex {
            return evaluateExists(userAttributes)
        }

        let userValues = userAttributes.attributeValues(forKey: key) ?? []
        if userValues.isEmpty {
            // Missing attribute — only negation comparators succeed.
            return FilterResult(isValid: comparator.isNegation, matchedAttributes: UserAttributes())
        }

        let filterValue = computeFilterValue(userAttributes)
        let userValue = userValues[0]
        let result = evaluate(userValue: userValue, userValues: userValues, filterValue: filterValue)

        let matched = UserAttributes()
        if result && id > 0 {
            matched.addAttribute(userValue, forKey: "matched_\(id)")
        }
        return FilterResult(isValid: result, matchedAttributes: matched)
    }

    // MARK: - Value resolution

    /// Resolve `value` taking expressions and "selected value" indirection into account.
    private func computeFilterValue(_ userAttributes: UserAttributes) -> Any? {
        var resolved: Any? = self.value

        if isExpression && ExpressionValidator.supports(dataType),
           let raw = resolved,
           let validator = ExpressionValidator.validator(for: dataType) {
            resolved = (try? validator.parseExpression(raw)) ?? resolved
        }

        if isSelectedVal, let attrName = resolved as? String,
           let selected = userAttributes.attributeValues(forKey: attrName), !selected.isEmpty {
            resolved = selected[0]
        } else if isSelectedVal {
            resolved = nil
        }
        return resolved
    }

    // MARK: - Evaluation

    private func evaluate(userValue: String, userValues: [String], filterValue: Any?) -> Bool {
        switch comparator {
        case .eq:           return evaluateEquals(userValue, filterValue)
        case .ne:           return !evaluateEquals(userValue, filterValue)
        case .lt:           return evaluateCompare(userValue, filterValue) < 0
        case .le:           return evaluateCompare(userValue, filterValue) <= 0
        case .gt:           return evaluateCompare(userValue, filterValue) > 0
        case .ge:           return evaluateCompare(userValue, filterValue) >= 0
        case .in:           return evaluateIn(userValues, filterValue)
        case .notIn:        return !evaluateIn(userValues, filterValue)
        case .bw:           return evaluateBetween(userValue, filterValue)
        case .ct:           return evaluateContains(userValue, filterValue)
        case .notContains:  return !evaluateContains(userValue, filterValue)
        case .sw:           return evaluateStartsWith(userValue, filterValue)
        case .ew:           return evaluateEndsWith(userValue, filterValue)
        case .re:           return evaluateRegex(userValue, filterValue)
        case .lk:           return evaluateLike(userValue, filterValue)
        case .ipo:          return evaluateIsPartOf(userValue, filterValue)
        case .ceq:          return evaluateCollectionEqual(userValues, filterValue)
        case .versionEq:    return RuleEvalUtils.compareVersions(userValue, stringify(filterValue)) == 0
        case .versionGt:    return RuleEvalUtils.compareVersions(userValue, stringify(filterValue))  > 0
        case .versionLt:    return RuleEvalUtils.compareVersions(userValue, stringify(filterValue))  < 0
        case .versionGe:    return RuleEvalUtils.compareVersions(userValue, stringify(filterValue)) >= 0
        case .versionLe:    return RuleEvalUtils.compareVersions(userValue, stringify(filterValue)) <= 0
        case .ex, .patch:
            FlagLog.warning("Unexpected comparator routed to evaluate(): \(comparator)")
            return false
        }
    }

    private func evaluateExists(_ userAttributes: UserAttributes) -> FilterResult {
        let userValues = userAttributes.attributeValues(forKey: key) ?? []
        let exists = !userValues.isEmpty

        var expected = true
        if let b = value as? Bool {
            expected = b
        } else if let s = value as? String {
            expected = (s.lowercased() == "true")
        }
        return FilterResult(isValid: exists == expected, matchedAttributes: UserAttributes())
    }

    private func evaluateEquals(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return userValue.isEmpty }

        if dataType.isNumeric {
            if let userNum = Double(userValue), let filterNum = toDouble(filterValue) {
                return userNum == filterNum
            }
            return userValue.caseInsensitiveCompare(stringify(filterValue)) == .orderedSame
        }

        if filterValue is Bool || dataType == .boolean {
            return (userValue.lowercased() == "true") == toBoolean(filterValue)
        }
        return userValue.caseInsensitiveCompare(stringify(filterValue)) == .orderedSame
    }

    private func evaluateCompare(_ userValue: String, _ filterValue: Any?) -> Int {
        guard let filterValue = filterValue else { return 1 }

        if dataType.isDate {
            if let epoch = filterValue as? Int64 {
                if let userEpoch = Int64(userValue) {
                    return userEpoch < epoch ? -1 : (userEpoch > epoch ? 1 : 0)
                }
                return RuleEvalUtils.compareDates(userValue, String(epoch))
            }
            return RuleEvalUtils.compareDates(userValue, stringify(filterValue))
        }

        if dataType.isNumeric,
           let userNum = Double(userValue),
           let filterNum = toDouble(filterValue) {
            return userNum < filterNum ? -1 : (userNum > filterNum ? 1 : 0)
        }

        return Self.lexCompare(userValue, stringify(filterValue))
    }

    private func evaluateIn(_ userValues: [String], _ filterValue: Any?) -> Bool {
        let filterList = Self.listForm(filterValue)
        for userValue in userValues {
            for fv in filterList {
                if userValue.caseInsensitiveCompare(stringify(fv).trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }

    private func evaluateBetween(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let list = filterValue as? [Any], list.count >= 2 else { return false }
        let start = list[0]
        let end = list[1]

        if dataType.isNumeric {
            guard let userNum = Double(userValue),
                  let startNum = toDouble(start),
                  let endNum = toDouble(end) else { return false }
            return userNum >= startNum && userNum <= endNum
        }
        if dataType.isDate {
            let startCmp = RuleEvalUtils.compareDates(userValue, stringify(start))
            let endCmp = RuleEvalUtils.compareDates(userValue, stringify(end))
            return startCmp >= 0 && endCmp <= 0
        }
        return Self.lexCompare(userValue, stringify(start)) >= 0
            && Self.lexCompare(userValue, stringify(end))   <= 0
    }

    private func evaluateContains(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }
        return userValue.lowercased().contains(stringify(filterValue).lowercased())
    }

    private func evaluateStartsWith(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }
        return userValue.lowercased().hasPrefix(stringify(filterValue).lowercased())
    }

    private func evaluateEndsWith(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }
        return userValue.lowercased().hasSuffix(stringify(filterValue).lowercased())
    }

    private func evaluateRegex(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }
        let pattern = stringify(filterValue)
        return RuleEvalUtils.regexMatches(userValue, pattern: pattern)
    }

    private func evaluateLike(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }
        let pattern = RuleEvalUtils.sqlLikeToRegex(stringify(filterValue))
        return RuleEvalUtils.regexMatches(userValue, pattern: "(?i)" + pattern)
    }

    private func evaluateIsPartOf(_ userValue: String, _ filterValue: Any?) -> Bool {
        guard let filterValue = filterValue else { return false }

        if let list = filterValue as? [Any] {
            return list.contains { CIDRMatcher.matches(ip: userValue, cidr: stringify($0)) }
        }
        return CIDRMatcher.matches(ip: userValue, cidr: stringify(filterValue))
    }

    private func evaluateCollectionEqual(_ userValues: [String], _ filterValue: Any?) -> Bool {
        let filterList = Self.listForm(filterValue)
        if filterList.isEmpty || userValues.count != filterList.count { return false }
        for fv in filterList {
            let target = stringify(fv)
            let found = userValues.contains {
                $0.caseInsensitiveCompare(target) == .orderedSame
            }
            if !found { return false }
        }
        return true
    }

    // MARK: - Coercion helpers

    private static func listForm(_ value: Any?) -> [Any] {
        if let list = value as? [Any] { return list }
        if let value = value { return [value] }
        return []
    }

    private static func lexCompare(_ a: String, _ b: String) -> Int {
        switch a.compare(b) {
        case .orderedAscending:  return -1
        case .orderedSame:       return 0
        case .orderedDescending: return 1
        }
    }

    private func toDouble(_ obj: Any?) -> Double? {
        if let n = obj as? NSNumber { return n.doubleValue }
        if let s = obj as? String { return Double(s) }
        return nil
    }

    private func toBoolean(_ obj: Any?) -> Bool {
        if let b = obj as? Bool { return b }
        if let s = obj as? String { return s.lowercased() == "true" }
        if let n = obj as? NSNumber { return n.boolValue }
        return false
    }

    /// `String(describing:)` would print Optional() — uses string coercion semantics.
    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            // JSON booleans deserialize as `__NSCFBoolean`; `stringValue` is "0"/"1", not "true"/"false".
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        return "\(value)"
    }
}
