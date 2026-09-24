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

/// Validator for date expressions such as `today+5d` or `today-3d`.
/// Returns `Int64` epoch-millis from `parseExpression(_:)`.
struct DateExpressionValidator: IExpressionValidator {

    /// Parsers for the supported date-expression formats.
    enum Parser: CaseIterable {

        /// `today+Nd` / `today-Nd` → epoch millis at the same time-of-day, ±N days.
        case todayOffset

        /// Compiled regex matching this parser's syntax.
        var regex: NSRegularExpression {
            switch self {
            case .todayOffset: return Self.todayOffsetRegex
            }
        }

        /// Compute the epoch-millis represented by `expression`.
        func parseDate(_ expression: String) -> Int64 {
            switch self {
            case .todayOffset: return Self.parseTodayOffset(expression)
            }
        }

        // MARK: - Compiled regexes (created once per process)

        private static let todayOffsetRegex: NSRegularExpression = {
            // `try!` is intentional — pattern is a compile-time constant.
            // swiftlint:disable:next force_try
            return try! NSRegularExpression(pattern: #"^today[+-]\d+d$"#)
        }()

        private static func parseTodayOffset(_ expression: String) -> Int64 {
            // expression = "today+Nd" or "today-Nd"
            //              012345 6...
            let chars = Array(expression)
            let sign: Character = chars[5]
            let daysString = String(chars[6..<(chars.count - 1)])
            let days = Int(daysString) ?? 0

            let offset = (sign == "+") ? days : -days
            let result = Calendar.current.date(byAdding: .day,
                                               value: offset,
                                               to: Date()) ?? Date()
            return Int64(result.timeIntervalSince1970 * 1000)
        }
    }

    func parseExpression(_ expression: String) throws -> Any {
        if expression.isEmpty {
            throw FlagClientError.invalidArgument(message: "Expression cannot be null or empty")
        }
        for parser in Parser.allCases {
            let range = NSRange(expression.startIndex..., in: expression)
            if parser.regex.firstMatch(in: expression, range: range) != nil {
                return parser.parseDate(expression)
            }
        }
        throw FlagClientError.invalidArgument(
            message: "Invalid expression for date: '\(expression)'. Did not match any valid regex. " +
                     "Supported formats: today+Nd, today-Nd"
        )
    }
}
