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

/// Composite filter expression with logical operators (`AND`/`OR`/`NEGATE`/`NONE`).
final class FilterExpression: IFilter {

    private(set) var op: FilterOperator
    private(set) var operands: [IFilter] = []

    init(_ op: FilterOperator) {
        self.op = op == .none ? .none : op
    }

    func setOperator(_ op: FilterOperator) {
        self.op = op
    }

    func addOperand(_ operand: IFilter) {
        operands.append(operand)
    }

    /// `true` when this expression wraps a single leaf filter under `NONE` — can be
    /// unwrapped via `toFilter()`. Returns whether the expression can convert to a filter.
    var isFilterConvertible: Bool {
        return op == .none && operands.count == 1 && (operands[0] is Filter)
    }

    /// Returns the underlying leaf filter when `isFilterConvertible` is `true`, else `nil`.
    func toFilter() -> IFilter? {
        return isFilterConvertible ? operands[0] : nil
    }

    func isValid(_ userAttributes: UserAttributes) -> Bool {
        return validateWithReturnValues(userAttributes).isValid
    }

    func validateWithReturnValues(_ userAttributes: UserAttributes) -> FilterResult {
        var resolved: Bool?
        let matched = UserAttributes()

        for operand in operands {
            switch op {
            case .and:
                if resolved == nil { resolved = true }
                let result = operand.validateWithReturnValues(userAttributes)
                resolved = (resolved ?? true) && result.isValid
                Self.mergeAttributes(target: matched, source: result.matchedAttributes)
                // Short-circuit on AND failure.
                if resolved == false {
                    return FilterResult(isValid: false, matchedAttributes: matched)
                }

            case .or:
                if resolved == nil { resolved = false }
                let result = operand.validateWithReturnValues(userAttributes)
                resolved = (resolved ?? false) || result.isValid
                if resolved == true {
                    return result
                }

            case .negate:
                // Accumulate with AND semantics; negate the final result after the loop.
                if resolved == nil { resolved = true }
                let result = operand.validateWithReturnValues(userAttributes)
                resolved = (resolved ?? true) && result.isValid
                Self.mergeAttributes(target: matched, source: result.matchedAttributes)

            case .none:
                return operand.validateWithReturnValues(userAttributes)
            }
        }

        // Empty expression is valid.
        var finalValid = resolved ?? true
        if op == .negate { finalValid.toggle() }
        return FilterResult(isValid: finalValid, matchedAttributes: matched)
    }

    private static func mergeAttributes(target: UserAttributes, source: UserAttributes) {
        for (key, values) in source.attributes {
            for value in values {
                target.addAttribute(value, forKey: key)
            }
        }
    }
}
