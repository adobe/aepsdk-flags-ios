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

/// Error thrown during SDK initialization (invalid configuration, network issues, etc).
/// Bridges to `NSError` for Objective-C consumers.
public enum FlagInitError: Error, LocalizedError, CustomNSError, Equatable {

    case missingConfiguration
    case missingEdgeDomain
    case invalidEdgeDomain(message: String)
    case missingImsOrg
    case missingSandboxName
    case missingClientId
    case initializationFailed(message: String, underlying: Error?)

    public static var errorDomain: String { "com.adobe.marketing.flags.init" }

    public var errorCode: Int {
        switch self {
        case .missingConfiguration:     return 2000
        case .missingEdgeDomain:        return 2005
        case .invalidEdgeDomain:        return 2006
        case .missingImsOrg:            return 2001
        case .missingSandboxName:       return 2002
        case .missingClientId:          return 2003
        case .initializationFailed:     return 2004
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Configuration is required"
        case .missingEdgeDomain:    return "Edge domain is required"
        case .invalidEdgeDomain(let message): return message
        case .missingImsOrg:        return "IMS organization is required"
        case .missingSandboxName:   return "Sandbox name is required"
        case .missingClientId:      return "Client ID is required"
        case .initializationFailed(let message, _): return message
        }
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let desc = errorDescription { info[NSLocalizedDescriptionKey] = desc }
        if case .initializationFailed(_, let underlying) = self, let underlying = underlying {
            info[NSUnderlyingErrorKey] = underlying
        }
        return info
    }

    public static func == (lhs: FlagInitError, rhs: FlagInitError) -> Bool {
        switch (lhs, rhs) {
        case (.missingConfiguration, .missingConfiguration),
             (.missingEdgeDomain, .missingEdgeDomain),
             (.missingImsOrg, .missingImsOrg),
             (.missingSandboxName, .missingSandboxName),
             (.missingClientId, .missingClientId):
            return true
        case (.invalidEdgeDomain(let a), .invalidEdgeDomain(let b)):
            return a == b
        case (.initializationFailed(let aMsg, _), .initializationFailed(let bMsg, _)):
            return aMsg == bMsg
        default:
            return false
        }
    }
}
