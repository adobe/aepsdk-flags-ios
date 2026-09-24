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

/// Pure-Swift CIDR matcher for IPv4 and IPv6 ranges.
/// All entry points are static; no caching state.
enum CIDRMatcher {

    /// `true` if `ipAddress` falls within `cidrRange`. Returns `false` for any malformed input.
    static func matches(ip ipAddress: String?, cidr cidrRange: String?) -> Bool {
        guard let ipAddress = ipAddress, let cidrRange = cidrRange else { return false }

        // If `cidrRange` has no `/`, it's a literal IP — straight equality.
        if !cidrRange.contains("/") {
            return ipAddress == cidrRange
        }

        let parts = cidrRange.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let maskBits = Int(parts[1]) else {
            FlagLog.warning("Invalid CIDR format: \(cidrRange)")
            return false
        }
        let rangeIp = String(parts[0])

        let addrIsV4 = isIPv4(ipAddress)
        let addrIsV6 = isIPv6(ipAddress)
        let rangeIsV4 = isIPv4(rangeIp)
        let rangeIsV6 = isIPv6(rangeIp)

        if addrIsV4 && rangeIsV4 {
            guard (0...32).contains(maskBits) else {
                FlagLog.warning("Invalid IPv4 CIDR mask bits: \(maskBits)")
                return false
            }
            return matchesIPv4(ipAddress, range: rangeIp, maskBits: maskBits)
        }

        if addrIsV6 && rangeIsV6 {
            guard (0...128).contains(maskBits) else {
                FlagLog.warning("Invalid IPv6 CIDR mask bits: \(maskBits)")
                return false
            }
            return matchesIPv6(ipAddress, range: rangeIp, maskBits: maskBits)
        }

        return false
    }

    // MARK: - Address validation

    static func isIPv4(_ ip: String?) -> Bool {
        guard let ip = ip, !ip.isEmpty else { return false }
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let num = Int(part), (0...255).contains(num) else { return false }
            // Strict IPv4 rejects leading zeros on multi-digit groups.
            if part.count > 1 && part.first == "0" { return false }
        }
        return true
    }

    static func isIPv6(_ ip: String?) -> Bool {
        guard let ip = ip, !ip.isEmpty else { return false }
        if !ip.contains(":") { return false }
        if ip.contains(":::") { return false }

        // IPv4-mapped IPv6 (e.g. `::ffff:192.168.1.1`)
        if ip.contains(".") {
            guard let lastColon = ip.lastIndex(of: ":") else { return false }
            let ipv4Part = String(ip[ip.index(after: lastColon)...])
            let ipv6Part = String(ip[..<lastColon])
            guard isIPv4(ipv4Part) else { return false }
            let normalized = ipv6Part.hasSuffix(":") ? String(ipv6Part.dropLast()) : ipv6Part
            return validateIPv6Part(normalized, allowTrailingColon: true)
        }
        return validateIPv6Part(ip, allowTrailingColon: false)
    }

    // MARK: - IPv4 / IPv6 matching

    private static func matchesIPv4(_ address: String, range: String, maskBits: Int) -> Bool {
        let addressInt = ipv4ToUInt32(address)
        let rangeInt = ipv4ToUInt32(range)
        let mask: UInt32 = maskBits == 0 ? 0 : UInt32.max &<< (32 - maskBits)
        return (addressInt & mask) == (rangeInt & mask)
    }

    private static func matchesIPv6(_ address: String, range: String, maskBits: Int) -> Bool {
        let addressBytes = ipv6ToBytes(address)
        let rangeBytes = ipv6ToBytes(range)

        let fullBytes = maskBits / 8
        let remainingBits = maskBits % 8

        for i in 0..<fullBytes where addressBytes[i] != rangeBytes[i] {
            return false
        }
        if remainingBits > 0 && fullBytes < 16 {
            let finalByteMask = UInt8((0xFF00 >> remainingBits) & 0xFF)
            return (addressBytes[fullBytes] & finalByteMask) == (rangeBytes[fullBytes] & finalByteMask)
        }
        return true
    }

    // MARK: - Comparison

    /// Compare two IP addresses. Returns `0` for equality, negative if `ip1 < ip2`, positive otherwise.
    /// Falls back to lexicographic comparison for mismatched / invalid types — on parse failure.
    static func compareIPAddress(_ ip1: String?, _ ip2: String?) -> Int {
        switch (ip1, ip2) {
        case (nil, nil): return 0
        case (nil, _):   return -1
        case (_, nil):   return 1
        case let (a?, b?):
            if isIPv4(a) && isIPv4(b) {
                let l1 = ipv4ToUInt32(a)
                let l2 = ipv4ToUInt32(b)
                return l1 < l2 ? -1 : (l1 > l2 ? 1 : 0)
            }
            if isIPv6(a) && isIPv6(b) {
                let b1 = ipv6ToBytes(a)
                let b2 = ipv6ToBytes(b)
                for i in 0..<16 {
                    if b1[i] != b2[i] { return Int(b1[i]) - Int(b2[i]) }
                }
                return 0
            }
            switch a.compare(b) {
            case .orderedAscending:  return -1
            case .orderedSame:       return 0
            case .orderedDescending: return 1
            }
        default:
            return 0
        }
    }

    // MARK: - Helpers

    private static func validateIPv6Part(_ ip: String, allowTrailingColon: Bool) -> Bool {
        if ip.isEmpty { return false }

        // Count occurrences of "::"
        var doubleColonCount = 0
        var searchStart = ip.startIndex
        while let range = ip.range(of: "::", range: searchStart..<ip.endIndex) {
            doubleColonCount += 1
            searchStart = range.upperBound
        }
        if doubleColonCount > 1 { return false }

        let groups: [Substring]
        if ip.contains("::") {
            let parts = ip.components(separatedBy: "::")
            let before = parts[0]
            let after = parts.count > 1 ? parts[1] : ""
            let beforeGroups = before.isEmpty ? [] : before.split(separator: ":")
            let afterGroups = after.isEmpty ? [] : after.split(separator: ":")
            if beforeGroups.count + afterGroups.count > 8 { return false }
            groups = beforeGroups + afterGroups
        } else {
            let split = ip.split(separator: ":", omittingEmptySubsequences: false)
            if !allowTrailingColon && split.count != 8 { return false }
            groups = split
        }

        for group in groups {
            if group.isEmpty || group.count > 4 { return false }
            guard let num = UInt32(group, radix: 16), num <= 0xFFFF else { return false }
        }
        return true
    }

    private static func ipv4ToUInt32(_ ip: String) -> UInt32 {
        let parts = ip.split(separator: ".")
        var result: UInt32 = 0
        for part in parts {
            let octet = UInt32(part) ?? 0
            result = (result &<< 8) &+ octet
        }
        return result
    }

    private static func ipv6ToBytes(_ ip: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16)

        if ip.contains(".") {
            guard let lastColon = ip.lastIndex(of: ":") else { return bytes }
            let ipv4Part = String(ip[ip.index(after: lastColon)...])
            let ipv6Part = String(ip[..<lastColon])

            let ipv4Parts = ipv4Part.split(separator: ".")
            if ipv4Parts.count == 4 {
                bytes[12] = UInt8(ipv4Parts[0]) ?? 0
                bytes[13] = UInt8(ipv4Parts[1]) ?? 0
                bytes[14] = UInt8(ipv4Parts[2]) ?? 0
                bytes[15] = UInt8(ipv4Parts[3]) ?? 0
            }
            let normalized = ipv6Part.hasSuffix(":") ? String(ipv6Part.dropLast()) : ipv6Part
            parseIPv6Groups(normalized, into: &bytes, maxBytes: 12)
            return bytes
        }

        parseIPv6Groups(ip, into: &bytes, maxBytes: 16)
        return bytes
    }

    private static func parseIPv6Groups(_ ip: String, into bytes: inout [UInt8], maxBytes: Int) {
        if ip.contains("::") {
            let parts = ip.components(separatedBy: "::")
            let before = parts[0]
            let after = parts.count > 1 ? parts[1] : ""

            let beforeGroups = before.isEmpty ? [] : before.split(separator: ":")
            let afterGroups = after.isEmpty ? [] : after.split(separator: ":")

            var byteIndex = 0
            for group in beforeGroups {
                let value = UInt32(group, radix: 16) ?? 0
                bytes[byteIndex] = UInt8((value >> 8) & 0xFF); byteIndex += 1
                bytes[byteIndex] = UInt8(value & 0xFF);        byteIndex += 1
            }
            byteIndex = maxBytes - afterGroups.count * 2
            for group in afterGroups {
                let value = UInt32(group, radix: 16) ?? 0
                bytes[byteIndex] = UInt8((value >> 8) & 0xFF); byteIndex += 1
                bytes[byteIndex] = UInt8(value & 0xFF);        byteIndex += 1
            }
        } else {
            let groups = ip.split(separator: ":")
            var byteIndex = 0
            for group in groups {
                let value = UInt32(group, radix: 16) ?? 0
                bytes[byteIndex] = UInt8((value >> 8) & 0xFF); byteIndex += 1
                bytes[byteIndex] = UInt8(value & 0xFF);        byteIndex += 1
            }
        }
    }
}
