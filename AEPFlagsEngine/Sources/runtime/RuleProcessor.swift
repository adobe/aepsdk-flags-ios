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

/// Rule processor for evaluating targeting criteria against user attributes.
/// Direct AST evaluator that walks a parsed criteria tree without building a `Filter`
/// tree (cheaper for one-shot evaluation).
/// Supported operators match the wire operator set — see `FilterComparator` for the full list.
final class RuleProcessor {

    private static let conditionAnd = "AND"
    private static let conditionOr  = "OR"
    private static let keyOperator  = "operator"
    private static let keyField     = "field"
    private static let keyAttr      = "attr"
    private static let keyValAlt    = "value"
    private static let keyVal       = "val"

    private let fieldDataTypeCache: [String: String]

    init(fieldDataTypeCache: [String: String]) {
        self.fieldDataTypeCache = fieldDataTypeCache
    }

    /// Evaluate `criteriaJson` against `userAttributes`. Returns `true` when the
    /// criteria is missing / nil (vacuous match), or when the criteria evaluates true.
    func evaluate(criteriaJson: String?, userAttributes: UserAttributes) -> Bool {
        guard let json = criteriaJson, !json.isEmpty, json != "null" else { return true }
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else {
            FlagLog.error("Failed to evaluate criteria: invalid JSON")
            return false
        }
        if parsed is NSNull { return true }

        let root: [String: Any]
        if let obj = parsed as? [String: Any] {
            if let criteria = obj["criteria"] {
                if criteria is NSNull { return true }
                root = (criteria as? [String: Any]) ?? [:]
            } else {
                root = obj
            }
        } else {
            return false
        }
        return evaluateNode(root, userAttributes: userAttributes)
    }

    // MARK: - Tree walk

    private func evaluateNode(_ node: [String: Any], userAttributes: UserAttributes) -> Bool {
        if let rules = node["and"] as? [Any] {
            return evaluateAnd(rules, userAttributes: userAttributes)
        }
        if let rules = node["or"] as? [Any] {
            return evaluateOr(rules, userAttributes: userAttributes)
        }
        if let rules = node["not"] as? [Any] {
            return !evaluateAnd(rules, userAttributes: userAttributes)
        }
        if let rules = node["negate"] as? [Any] {
            return !evaluateAnd(rules, userAttributes: userAttributes)
        }
        if let condition = node["condition"] as? String, let rules = node["rules"] as? [Any] {
            if condition.caseInsensitiveCompare(Self.conditionAnd) == .orderedSame {
                return evaluateAnd(rules, userAttributes: userAttributes)
            }
            if condition.caseInsensitiveCompare(Self.conditionOr) == .orderedSame {
                return evaluateOr(rules, userAttributes: userAttributes)
            }
        }
        // Compact ({"operator", "attr", "val"}) or legacy ({"operator", "field", "value"})
        if node[Self.keyAttr] != nil && node[Self.keyOperator] != nil {
            return evaluateRule(node, userAttributes: userAttributes)
        }
        if node[Self.keyField] != nil && node[Self.keyOperator] != nil {
            return evaluateRule(node, userAttributes: userAttributes)
        }
        return true
    }

    private func evaluateAnd(_ rules: [Any], userAttributes: UserAttributes) -> Bool {
        for rule in rules {
            guard let dict = rule as? [String: Any],
                  evaluateNode(dict, userAttributes: userAttributes) else {
                return false
            }
        }
        return true
    }

    private func evaluateOr(_ rules: [Any], userAttributes: UserAttributes) -> Bool {
        for rule in rules {
            if let dict = rule as? [String: Any],
               evaluateNode(dict, userAttributes: userAttributes) {
                return true
            }
        }
        return false
    }

    // MARK: - Leaf rule

    private func evaluateRule(_ rule: [String: Any], userAttributes: UserAttributes) -> Bool {
        let field = (rule[Self.keyAttr] as? String) ?? (rule[Self.keyField] as? String)
        guard let field = field else {
            FlagLog.warning("Rule missing field/attr: \(rule)")
            return true
        }
        guard let operatorRaw = rule[Self.keyOperator] as? String else { return false }
        let valueElement: Any? = rule[Self.keyVal] ?? rule[Self.keyValAlt]

        let upper = operatorRaw.uppercased()

        if upper == "EXISTS" || upper == "EX" {
            return evaluateExists(field: field, value: valueElement, userAttributes: userAttributes)
        }

        let userValues = userAttributes.attributeValues(forKey: field) ?? []
        if userValues.isEmpty {
            // Missing attribute — only negation operators succeed.
            return upper.contains("NOT") || upper == "NOT_IN"
        }
        let userValue = userValues[0]

        switch upper {
        case "EQUALS", "EQ":
            return evaluateEquals(userValue, valueElement)
        case "NOT_EQUALS", "NEQ", "NE":
            return !evaluateEquals(userValue, valueElement)
        case "IN":
            return evaluateIn(userValues, valueElement)
        case "NOT_IN":
            return !evaluateIn(userValues, valueElement)
        case "CONTAINS", "CT":
            return evaluateContains(userValue, valueElement)
        case "NOT_CONTAINS":
            return !evaluateContains(userValue, valueElement)
        case "STARTS_WITH", "SW":
            return evaluateStartsWith(userValue, valueElement)
        case "ENDS_WITH", "EW":
            return evaluateEndsWith(userValue, valueElement)
        case "GREATER_THAN", "GT":
            return evaluateGreaterThan(userValue, valueElement, field: field)
        case "LESS_THAN", "LT":
            return evaluateLessThan(userValue, valueElement, field: field)
        case "GREATER_THAN_OR_EQUALS", "GTE", "GE":
            return evaluateGreaterThanOrEquals(userValue, valueElement, field: field)
        case "LESS_THAN_OR_EQUALS", "LTE", "LE":
            return evaluateLessThanOrEquals(userValue, valueElement, field: field)
        case "BETWEEN", "BW":
            return evaluateBetween(userValue, valueElement, field: field)
        case "MATCHES_REGEX", "REGEX", "RE":
            return RuleEvalUtils.regexMatches(userValue, pattern: stringify(valueElement))
        case "LIKE", "LK":
            return RuleEvalUtils.regexMatches(userValue, pattern: "(?i)" + RuleEvalUtils.sqlLikeToRegex(stringify(valueElement)))
        case "IS_PART_OF", "IPO", "IP_IN_CIDR":
            return evaluateIsPartOf(userValue, valueElement)
        case "COLLECTION_EQUAL", "CEQ":
            return evaluateCollectionEqual(userValues, valueElement)
        case "VERSION_GREATER_THAN", "VERSION_GT":
            return RuleEvalUtils.compareVersions(userValue, stringify(valueElement)) > 0
        case "VERSION_LESS_THAN", "VERSION_LT":
            return RuleEvalUtils.compareVersions(userValue, stringify(valueElement)) < 0
        case "VERSION_EQUALS", "VERSION_EQ":
            return RuleEvalUtils.compareVersions(userValue, stringify(valueElement)) == 0
        case "VERSION_GREATER_THAN_OR_EQUALS", "VERSION_GTE", "VERSION_GE":
            return RuleEvalUtils.compareVersions(userValue, stringify(valueElement)) >= 0
        case "VERSION_LESS_THAN_OR_EQUALS", "VERSION_LTE", "VERSION_LE":
            return RuleEvalUtils.compareVersions(userValue, stringify(valueElement)) <= 0
        default:
            FlagLog.warning("Unknown operator: \(operatorRaw)")
            return false
        }
    }

    // MARK: - Operator implementations

    private func evaluateEquals(_ userValue: String, _ target: Any?) -> Bool {
        guard let target = target else { return false }

        if let b = target as? Bool, isBoolean(target as? NSNumber) {
            return (userValue.lowercased() == "true") == b
        }
        if let n = target as? NSNumber, !isBoolean(n) {
            if let userNum = Double(userValue) { return userNum == n.doubleValue }
            return userValue == n.stringValue
        }
        if let s = target as? String {
            return userValue.caseInsensitiveCompare(s) == .orderedSame
        }
        return userValue == "\(target)"
    }

    private func evaluateIn(_ userValues: [String], _ target: Any?) -> Bool {
        guard let array = target as? [Any] else { return false }
        for userValue in userValues {
            for element in array {
                let targetStr = stringify(element)
                if userValue.caseInsensitiveCompare(targetStr) == .orderedSame {
                    return true
                }
            }
        }
        return false
    }

    private func evaluateContains(_ userValue: String, _ target: Any?) -> Bool {
        guard let target = target else { return false }
        return userValue.lowercased().contains(stringify(target).lowercased())
    }

    private func evaluateStartsWith(_ userValue: String, _ target: Any?) -> Bool {
        guard let target = target else { return false }
        return userValue.lowercased().hasPrefix(stringify(target).lowercased())
    }

    private func evaluateEndsWith(_ userValue: String, _ target: Any?) -> Bool {
        guard let target = target else { return false }
        return userValue.lowercased().hasSuffix(stringify(target).lowercased())
    }

    private func evaluateGreaterThan(_ userValue: String, _ target: Any?, field: String) -> Bool {
        let dataType = fieldDataType(forField: field)
        if isDateType(dataType) {
            return RuleEvalUtils.compareDates(userValue, stringify(target)) > 0
        }
        if let userNum = Double(userValue),
           let targetNum = (target as? NSNumber)?.doubleValue ?? Double(stringify(target)) {
            return userNum > targetNum
        }
        return userValue > stringify(target)
    }

    private func evaluateLessThan(_ userValue: String, _ target: Any?, field: String) -> Bool {
        let dataType = fieldDataType(forField: field)
        if isDateType(dataType) {
            return RuleEvalUtils.compareDates(userValue, stringify(target)) < 0
        }
        if let userNum = Double(userValue),
           let targetNum = (target as? NSNumber)?.doubleValue ?? Double(stringify(target)) {
            return userNum < targetNum
        }
        return userValue < stringify(target)
    }

    private func evaluateGreaterThanOrEquals(_ userValue: String, _ target: Any?, field: String) -> Bool {
        return evaluateEquals(userValue, target) || evaluateGreaterThan(userValue, target, field: field)
    }

    private func evaluateLessThanOrEquals(_ userValue: String, _ target: Any?, field: String) -> Bool {
        return evaluateEquals(userValue, target) || evaluateLessThan(userValue, target, field: field)
    }

    private func evaluateBetween(_ userValue: String, _ target: Any?, field: String) -> Bool {
        guard let range = target as? [Any], range.count == 2 else { return false }
        return evaluateGreaterThanOrEquals(userValue, range[0], field: field)
            && evaluateLessThanOrEquals(userValue, range[1], field: field)
    }

    private func evaluateExists(field: String,
                                value: Any?,
                                userAttributes: UserAttributes) -> Bool {
        let userValues = userAttributes.attributeValues(forKey: field) ?? []
        let exists = !userValues.isEmpty

        var expected = true
        if let b = value as? Bool { expected = b }
        return exists == expected
    }

    private func evaluateIsPartOf(_ userValue: String, _ target: Any?) -> Bool {
        if let list = target as? [Any] {
            for cidr in list where CIDRMatcher.matches(ip: userValue, cidr: stringify(cidr)) {
                return true
            }
            return false
        }
        return CIDRMatcher.matches(ip: userValue, cidr: stringify(target))
    }

    private func evaluateCollectionEqual(_ userValues: [String], _ target: Any?) -> Bool {
        guard let array = target as? [Any], userValues.count == array.count else { return false }
        for element in array {
            let targetStr = stringify(element)
            let found = userValues.contains { $0.caseInsensitiveCompare(targetStr) == .orderedSame }
            if !found { return false }
        }
        return true
    }

    // MARK: - Helpers

    private func fieldDataType(forField field: String) -> String? {
        return fieldDataTypeCache[field]
    }

    private func isDateType(_ raw: String?) -> Bool {
        guard let raw = raw?.uppercased() else { return false }
        return raw == "DATE" || raw == "DATETIME" || raw == "DATE_TIME"
    }

    private func isBoolean(_ number: NSNumber?) -> Bool {
        guard let number = number else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func stringify(_ value: Any?) -> String {
        guard let value = value else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return "\(value)"
    }
}
