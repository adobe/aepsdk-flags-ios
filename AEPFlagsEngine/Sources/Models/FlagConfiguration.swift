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

/// Immutable configuration for the Flags Mobile SDK.
/// Bridges to Obj-C as `AEPMobileFlagConfiguration`.
/// Optional caller-supplied
/// caller-supplied `URLSession`. The SDK does NOT invalidate the supplied session on
/// `close()` — the caller retains ownership.
@objc(AEPMobileFlagConfiguration)
public final class FlagConfiguration: NSObject {

    @objc public let edgeDomain: String
    @objc public let imsOrg: String
    @objc public let sandboxName: String
    @objc public let clientId: String
    /// Caller-supplied `URLSession`. `nil` means the SDK creates its own internally.
    @objc public let urlSession: URLSession?
    /// SDK version reported to the backend as the `sdkVersion` request parameter. Injected by the
    /// host so a single version drives the whole product. When `nil`, the parameter is sent without a value.
    @objc public let sdkVersion: String?

    fileprivate init(edgeDomain: String,
                     imsOrg: String,
                     sandboxName: String,
                     clientId: String,
                     urlSession: URLSession?,
                     sdkVersion: String?) {
        self.edgeDomain = edgeDomain
        self.imsOrg = imsOrg
        self.sandboxName = sandboxName
        self.clientId = clientId
        self.urlSession = urlSession
        self.sdkVersion = sdkVersion
        super.init()
    }

    /// Convenience factory for a fresh `Builder`.
    @objc public static func builder() -> Builder {
        return Builder()
    }

    /// Builder for `FlagConfiguration`.
    @objc(AEPMobileFlagConfigurationBuilder)
    public final class Builder: NSObject {

        private var _edgeDomain: String?
        private var _imsOrg: String?
        private var _sandboxName: String?
        private var _clientId: String?
        private var _urlSession: URLSession?
        private var _sdkVersion: String?

        @objc public override init() {
            super.init()
        }

        /// Set the edge domain for feature requests. Required. Host only — no scheme or path.
        @discardableResult
        @objc public func edgeDomain(_ edgeDomain: String) -> Builder {
            self._edgeDomain = edgeDomain
            return self
        }

        @discardableResult
        @objc public func imsOrg(_ imsOrg: String) -> Builder {
            self._imsOrg = imsOrg
            return self
        }

        @discardableResult
        @objc public func sandboxName(_ sandboxName: String) -> Builder {
            self._sandboxName = sandboxName
            return self
        }

        @discardableResult
        @objc public func clientId(_ clientId: String) -> Builder {
            self._clientId = clientId
            return self
        }

        /// Supply an existing `URLSession`. The SDK uses it directly and never invalidates it.
        @discardableResult
        @objc public func urlSession(_ urlSession: URLSession) -> Builder {
            self._urlSession = urlSession
            return self
        }

        /// Set the SDK version reported to the backend as the `sdkVersion` request parameter.
        @discardableResult
        @objc public func sdkVersion(_ sdkVersion: String) -> Builder {
            self._sdkVersion = sdkVersion
            return self
        }

        /// Build the immutable configuration.
        @objc(buildAndReturnError:)
        public func build() throws -> FlagConfiguration {
            let imsOrg = (_imsOrg ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let sandbox = (_sandboxName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let clientId = (_clientId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let edgeDomain = try Self.normalizeEdgeDomain(_edgeDomain)

            if imsOrg.isEmpty { throw FlagInitError.missingImsOrg }
            if sandbox.isEmpty { throw FlagInitError.missingSandboxName }
            if clientId.isEmpty { throw FlagInitError.missingClientId }

            let sdkVersion = _sdkVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
            return FlagConfiguration(edgeDomain: edgeDomain,
                                   imsOrg: imsOrg,
                                   sandboxName: sandbox,
                                   clientId: clientId,
                                   urlSession: _urlSession,
                                   sdkVersion: (sdkVersion?.isEmpty == false) ? sdkVersion : nil)
        }

        private static func normalizeEdgeDomain(_ raw: String?) throws -> String {
            guard let raw = raw else {
                throw FlagInitError.missingEdgeDomain
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw FlagInitError.missingEdgeDomain
            }
            if trimmed.contains("://") {
                throw FlagInitError.invalidEdgeDomain(message: "Edge domain must not include a URL scheme")
            }
            if trimmed.contains("/") {
                throw FlagInitError.invalidEdgeDomain(message: "Edge domain must not include a path")
            }
            return trimmed
        }
    }

    /// Safe summary for logging — does not include `imsOrg` or `sandboxName`.
    public override var description: String {
        return "<FlagConfiguration edgeDomain=\(edgeDomain) clientId=\(clientId)>"
    }
}
