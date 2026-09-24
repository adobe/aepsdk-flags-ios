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

/// Internal helpers shared by `Filter` and `RuleProcessor`. Centralizes regex matching,
/// version comparison, and date parsing so both evaluation paths produce identical results.
enum RuleEvalUtils {

    // MARK: - Regex

    /// `true` if `value` fully matches `pattern` (anchored full match).
    /// Returns `false` for any invalid regex.
    static func regexMatches(_ value: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(value.startIndex..., in: value)
            if let m = regex.firstMatch(in: value, range: range) {
                return m.range == range
            }
            return false
        } catch {
            FlagLog.error("Invalid regex pattern '\(pattern)': \(error)")
            return false
        }
    }

    /// Convert a SQL `LIKE` pattern to a regex: `%` → `.*`, `_` → `.`. Other regex
    /// meta-characters (`.`, `*`) are escaped.
    static func sqlLikeToRegex(_ pattern: String) -> String {
        return pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "%", with: ".*")
            .replacingOccurrences(of: "_", with: ".")
    }

    // MARK: - Versions

    /// Compare dotted version strings (e.g. `"1.2.3"` vs `"1.10"`).
    /// Numeric prefix of each part is taken (e.g. `"1-SNAPSHOT"` → `1`).
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let parts1 = a.split(separator: ".", omittingEmptySubsequences: false)
        let parts2 = b.split(separator: ".", omittingEmptySubsequences: false)
        let maxLen = max(parts1.count, parts2.count)

        for i in 0..<maxLen {
            let v1 = i < parts1.count ? parseVersionPart(String(parts1[i])) : 0
            let v2 = i < parts2.count ? parseVersionPart(String(parts2[i])) : 0
            if v1 != v2 { return v1 < v2 ? -1 : 1 }
        }
        return 0
    }

    private static func parseVersionPart(_ part: String) -> Int {
        var digits = ""
        for ch in part {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
            } else {
                break
            }
        }
        return Int(digits) ?? 0
    }

    // MARK: - Dates

    /// Compare two date strings. Returns `0` on parse failure.
    static func compareDates(_ a: String, _ b: String) -> Int {
        guard let d1 = parseDate(a), let d2 = parseDate(b) else {
            FlagLog.error("Failed to parse date: '\(a)' or '\(b)'")
            return 0
        }
        if d1 == d2 { return 0 }
        return d1 < d2 ? -1 : 1
    }

    /// Try a small set of accepted date formats, in order of specificity.
    /// New `DateFormatter` instances are created per call because `DateFormatter` is
    /// not thread-safe and sharing static instances across concurrent evaluations
    /// would cause data races.
    static func parseDate(_ value: String) -> Date? {
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ]
        for pattern in patterns {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = pattern
            if let date = df.date(from: value) { return date }
        }
        return nil
    }
}
