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

/// Filter comparators / operators used by leaf `Filter` nodes.
/// Each case carries the set of wire aliases
/// (upper-case) that resolve to it via `FilterComparator.from(_:)`.
enum FilterComparator: CaseIterable {
    // Relational
    case eq, ne, lt, le, gt, ge
    // Set operations
    case `in`, notIn, bw
    // String operations
    case ct, notContains, sw, ew, lk, re
    // Special
    case ex, ipo, ceq, patch
    // Version
    case versionEq, versionGt, versionLt, versionGe, versionLe

    /// All wire aliases this comparator answers to (upper-case).
    var aliases: [String] {
        switch self {
        case .eq:           return ["EQ", "EQUALS"]
        case .ne:           return ["NE", "NOT_EQUALS", "NEQ"]
        case .lt:           return ["LT", "LESS_THAN"]
        case .le:           return ["LE", "LESS_THAN_OR_EQUALS", "LTE"]
        case .gt:           return ["GT", "GREATER_THAN"]
        case .ge:           return ["GE", "GREATER_THAN_OR_EQUALS", "GTE"]
        case .in:           return ["IN"]
        case .notIn:        return ["NOT_IN"]
        case .bw:           return ["BW", "BETWEEN"]
        case .ct:           return ["CT", "CONTAINS"]
        case .notContains:  return ["NOT_CONTAINS"]
        case .sw:           return ["SW", "STARTS_WITH"]
        case .ew:           return ["EW", "ENDS_WITH"]
        case .lk:           return ["LK", "LIKE"]
        case .re:           return ["RE", "REGEX", "MATCHES_REGEX"]
        case .ex:           return ["EX", "EXISTS"]
        case .ipo:          return ["IPO", "IS_PART_OF", "IP_IN_CIDR"]
        case .ceq:          return ["CEQ", "COLLECTION_EQUAL"]
        case .patch:        return ["PATCH"]
        case .versionEq:    return ["VERSION_EQ", "VERSION_EQUALS"]
        case .versionGt:    return ["VERSION_GT", "VERSION_GREATER_THAN"]
        case .versionLt:    return ["VERSION_LT", "VERSION_LESS_THAN"]
        case .versionGe:    return ["VERSION_GE", "VERSION_GREATER_THAN_OR_EQUALS", "VERSION_GTE"]
        case .versionLe:    return ["VERSION_LE", "VERSION_LESS_THAN_OR_EQUALS", "VERSION_LTE"]
        }
    }

    /// Parse a wire code (case-insensitive). Returns `nil` for empty / unrecognized input.
    static func from(_ value: String?) -> FilterComparator? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        for comparator in Self.allCases where comparator.aliases.contains(upper) {
            return comparator
        }
        return nil
    }

    /// `true` for relational equality / ordering comparators (`<`, `<=`, `>`, `>=`, `==`, `!=`).
    var isRelationalEquality: Bool {
        switch self {
        case .lt, .le, .gt, .ge, .eq, .ne: return true
        default: return false
        }
    }

    /// `true` for negation comparators — i.e. absence of the attribute satisfies the filter.
    var isNegation: Bool {
        switch self {
        case .ne, .notIn, .notContains: return true
        default: return false
        }
    }

    var isStringOperator: Bool {
        switch self {
        case .ct, .sw, .ew, .lk, .re: return true
        default: return false
        }
    }

    var isVersionOperator: Bool {
        switch self {
        case .versionEq, .versionGt, .versionLt, .versionGe, .versionLe: return true
        default: return false
        }
    }
}
