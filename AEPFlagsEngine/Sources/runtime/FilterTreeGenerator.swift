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

/// Compiles a JSON criteria string into an executable `IFilter` tree.
/// Uses `JSONSerialization` to produce an untyped tree; type checks discriminate
/// `[Any]` / `[String: Any]` / primitives.
final class FilterTreeGenerator {

    /// Optional registry of named lists referenced by the `isNamedListValue` flag.
    protocol NamedListCache {
        func namedListValues(name: String) -> Any?
    }

    // JSON keys
    private static let keyCriteria = "criteria"
    private static let keyAttr     = "attr"
    private static let keyKey      = "key"
    private static let keyField    = "field"
    private static let keyOperator = "operator"
    private static let keyValue    = "val"
    private static let keyValueAlt = "value"
    private static let keyId       = "id"
    private static let keyParams   = "params"
    private static let keyIsExpr   = "isExpression"
    private static let keyIsSelVal = "isSelectedVal"
    private static let keyIsNamed  = "isNamedListValue"

    private let fieldDataTypeCache: [String: String]
    private let namedListCache: NamedListCache?

    init(fieldDataTypeCache: [String: String], namedListCache: NamedListCache? = nil) {
        self.fieldDataTypeCache = fieldDataTypeCache
        self.namedListCache = namedListCache
    }

    // MARK: - Entry points

    /// Compile `criteriaJson` into a filter tree. `EmptyFilter` for nil/empty,
    /// `RejectingFilter` (when `rejectOnParseError` is set) for malformed input.
    func filterTree(_ criteriaJson: String?,
                    isRootTagPresent: Bool = true,
                    rejectOnParseError: Bool = false) -> IFilter {
        guard let json = criteriaJson, !json.isEmpty, json != "null" else {
            return EmptyFilter()
        }

        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []) else {
            FlagLog.error("Error parsing filter tree JSON")
            return rejectOnParseError ? RejectingFilter() : EmptyFilter()
        }
        if parsed is NSNull { return EmptyFilter() }

        var filterConfig: Any = parsed
        if isRootTagPresent {
            if let root = parsed as? [String: Any], let inner = root[Self.keyCriteria] {
                filterConfig = inner
            } else if !(parsed is [String: Any]) {
                FlagLog.warning("Root tag 'criteria' not found, treating entire JSON as criteria")
            }
        }
        return parseTree(filterConfig, rejectOnParseError: rejectOnParseError)
    }

    /// Compile a JSON sub-tree (already parsed). Public for `FilterService`'s map → filter flow.
    func parseTree(_ configValue: Any?, rejectOnParseError: Bool) -> IFilter {
        guard let value = configValue, !(value is NSNull) else { return EmptyFilter() }

        // Array → list of filters under NONE (unwrap if single).
        if let array = value as? [Any] {
            let expression = parseTreeHelper(operator: .none, configValue: array)
            return expression.toFilter() ?? expression
        }

        // Object — could be logical operator wrapper, condition/rules wrapper, or leaf.
        if let obj = value as? [String: Any] {
            if obj.isEmpty { return EmptyFilter() }

            for key in obj.keys {
                let logical = FilterOperator.from(code: key)
                if logical != .none {
                    return parseTreeHelper(operator: logical, configValue: obj[key])
                }
            }

            if let condition = obj["condition"] as? String, let rules = obj["rules"] {
                var op = FilterOperator.from(code: condition)
                if op == .none { op = .and }
                return parseTreeHelper(operator: op, configValue: rules)
            }

            return parseFilter(obj)
        }

        FlagLog.warning("Unexpected config value type: \(type(of: value))")
        return rejectOnParseError ? RejectingFilter() : EmptyFilter()
    }

    // MARK: - Parsing helpers

    private func parseTreeHelper(operator op: FilterOperator, configValue: Any?) -> FilterExpression {
        let expression = FilterExpression(op)
        guard let value = configValue, !(value is NSNull) else { return expression }

        if let array = value as? [Any] {
            for element in array { addOperand(expression, element: element) }
        } else {
            addOperand(expression, element: value)
        }
        return expression
    }

    private func addOperand(_ expression: FilterExpression, element: Any) {
        guard let obj = element as? [String: Any], !obj.isEmpty else { return }

        for key in obj.keys {
            let logical = FilterOperator.from(code: key)
            if logical != .none {
                expression.addOperand(parseTreeHelper(operator: logical, configValue: obj[key]))
                return
            }
        }
        expression.addOperand(parseFilter(obj))
    }

    private func parseFilter(_ filterConfig: [String: Any]) -> IFilter {
        let key = (filterConfig[Self.keyAttr] as? String)
            ?? (filterConfig[Self.keyKey] as? String)
            ?? (filterConfig[Self.keyField] as? String)
            ?? ""

        let valueRaw: Any? = filterConfig[Self.keyValue] ?? filterConfig[Self.keyValueAlt]
        guard valueRaw != nil else { return EmptyFilter() }

        let operatorCode = filterConfig[Self.keyOperator] as? String
        let comparator: FilterComparator = FilterComparator.from(operatorCode) ?? {
            FlagLog.warning("Invalid operator: \(operatorCode ?? "<nil>")")
            return .eq
        }()

        var id = 0
        if let idNum = filterConfig[Self.keyId] as? NSNumber { id = idNum.intValue }

        var isExpression = false
        var isSelectedVal = false
        var isNamedListValue = false
        if let params = filterConfig[Self.keyParams] as? [String: Any] {
            if let v = params[Self.keyIsExpr]    as? Bool { isExpression = v }
            if let v = params[Self.keyIsSelVal]  as? Bool { isSelectedVal = v }
            if let v = params[Self.keyIsNamed]   as? Bool { isNamedListValue = v }
        }

        let dataType = fieldDataType(forKey: key)
        let value = convertValue(valueRaw,
                                 dataType: dataType,
                                 isNamedListValue: isNamedListValue)

        return Filter(key: key,
                      value: value,
                      comparator: comparator,
                      dataType: dataType,
                      id: id,
                      isExpression: isExpression,
                      isSelectedVal: isSelectedVal)
    }

    private func fieldDataType(forKey key: String) -> FieldDataType {
        guard !key.isEmpty else { return .string }
        return FieldDataType.from(fieldDataTypeCache[key])
    }

    private func convertValue(_ value: Any?,
                              dataType: FieldDataType,
                              isNamedListValue: Bool) -> Any? {
        guard let value = value, !(value is NSNull) else { return nil }

        if isNamedListValue, let cache = namedListCache, let name = value as? String,
           let resolved = cache.namedListValues(name: name) {
            return resolved
        }

        if let array = value as? [Any] {
            return array.map { convertPrimitive($0, dataType: dataType) as Any }
        }
        return convertPrimitive(value, dataType: dataType)
    }

    private func convertPrimitive(_ element: Any?, dataType: FieldDataType) -> Any? {
        guard let element = element, !(element is NSNull) else { return nil }

        // NSNumber from JSONSerialization needs to disambiguate Bool / Int / Double.
        if let number = element as? NSNumber {
            if isBoolean(number) { return number.boolValue }
            switch dataType {
            case .integer: return number.intValue
            case .long:    return number.int64Value
            case .decimal: return number.doubleValue
            default:       return number
            }
        }
        if let string = element as? String { return string }
        if element is [Any] || element is [String: Any] { return element }
        return "\(element)"
    }

    /// Distinguish `Bool`-backed NSNumber from numeric NSNumber.
    /// `JSONSerialization` packs both as NSNumber, so the only reliable check is the object type id.
    private func isBoolean(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
