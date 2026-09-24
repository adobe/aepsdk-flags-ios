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

/// HTTP client for the Flags Edge service (features + metadata).
/// Uses `URLSession` with optional caller sharing.
final class APIProxy {

    /// Fully resolved Edge base URL (trailing slash stripped). Internal for unit tests.
    internal let edgeBaseUrl: String
    /// IMS organization identifier for `x-gw-ims-org-id`. Internal for unit tests.
    internal let imsOrg: String
    /// Sandbox name for `x-sandbox-name`. Internal for unit tests.
    internal let sandboxName: String
    /// SDK version reported as the `sdkVersion` query parameter. Injected by the host extension
    /// (the single source of truth). When `nil`, the parameter is sent without a value. Internal for unit tests.
    internal let sdkVersion: String?
    /// Active `URLSession` (caller-owned or SDK-owned). Internal for unit tests.
    internal let urlSession: URLSession
    /// `true` when the SDK constructed `urlSession` and will invalidate it on `shutdown()`.
    internal let ownsSession: Bool

    /// SDK timeout settings applied to owned sessions (applied to SDK-owned URLSession instances).
    internal let sdkConnectTimeoutSeconds: TimeInterval = FlagConstants.HTTP.CONNECT_TIMEOUT_SECONDS
    internal let sdkReadTimeoutSeconds: TimeInterval = FlagConstants.HTTP.READ_TIMEOUT_SECONDS
    internal let sdkWriteTimeoutSeconds: TimeInterval = FlagConstants.HTTP.WRITE_TIMEOUT_SECONDS

    /// Validates configuration without instantiating.
    static func isValidEdgeBaseUrl(_ raw: String?) -> Bool {
        guard let raw = raw else { return false }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// - Parameters:
    ///   - edgeBaseUrl: HTTPS base URL for feature requests (no trailing slash required).
    ///   - imsOrg: IMS organization identifier for `x-gw-ims-org-id`.
    ///   - sandboxName: Sandbox name for `x-sandbox-name`.
    ///   - sharedSession: Caller-owned `URLSession` to reuse, or `nil` to create an SDK-owned session with SDK timeouts.
    ///   - sdkVersion: SDK version for the `sdkVersion` query parameter, injected by the host. When `nil`, the parameter is sent without a value.
    init(edgeBaseUrl: String, imsOrg: String, sandboxName: String, sharedSession: URLSession?, sdkVersion: String? = nil) {
        let trimmedBase = edgeBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedBase.isEmpty, "edgeBaseUrl must not be null or blank")
        self.edgeBaseUrl = trimmedBase.hasSuffix("/") ? String(trimmedBase.dropLast()) : trimmedBase
        self.sdkVersion = sdkVersion

        let trimmedOrg = imsOrg.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedOrg.isEmpty, "imsOrg must not be null or blank")
        self.imsOrg = trimmedOrg

        let trimmedSandbox = sandboxName.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmedSandbox.isEmpty, "sandboxName must not be null or blank")
        self.sandboxName = trimmedSandbox

        if let shared = sharedSession {
            self.urlSession = shared
            self.ownsSession = false
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = sdkReadTimeoutSeconds
            config.timeoutIntervalForResource = sdkWriteTimeoutSeconds
            config.waitsForConnectivity = true
            self.urlSession = URLSession(configuration: config)
            self.ownsSession = true
        }
    }

    /// Fetch the combined feature payload.
    /// Sends `contextVersion` as a query parameter when non-empty and `If-None-Match` when `etag` is non-empty.
    func getFeatures(clientId: String, contextVersion: String?, etag: String?) throws -> FlagApiResponse {
        do {
            return try fetchFeatures(clientId: clientId, contextVersion: contextVersion, etag: etag)
        } catch let error as FlagClientError {
            throw error
        } catch {
            throw FlagClientError.operationFailed(message: "Failed to fetch features", underlying: error)
        }
    }

    /// Evicts idle connections from the SDK-owned session. No-op when a caller-supplied
    /// session is in use (when the session is SDK-owned).
    func evictIdleConnections() {
        guard ownsSession else { return }
        urlSession.configuration.urlCache?.removeAllCachedResponses()
    }

    /// Shuts down the SDK-owned session. No-op for caller-supplied sessions.
    func shutdown() {
        guard ownsSession else { return }
        urlSession.invalidateAndCancel()
    }

    // MARK: - Private

    private func fetchFeatures(clientId: String, contextVersion: String?, etag: String?) throws -> FlagApiResponse {
        let url = try buildFeatureRequestURL(clientId: clientId, contextVersion: contextVersion)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(FlagConstants.Headers.ACCEPT_JSON, forHTTPHeaderField: FlagConstants.Headers.ACCEPT)
        request.setValue(imsOrg, forHTTPHeaderField: FlagConstants.Headers.IMS_ORG)
        request.setValue(sandboxName, forHTTPHeaderField: FlagConstants.Headers.SANDBOX_NAME)
        if let etag = etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: FlagConstants.Headers.IF_NONE_MATCH)
        }

        let (data, response) = try perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw FlagClientError.networkFailure(statusCode: -1, message: "Invalid response")
        }

        let responseEtag = Self.headerValue(http, field: FlagConstants.Headers.ETAG)

        if http.statusCode == 304 {
            return FlagApiResponse(fgxResponse: nil, etag: responseEtag, isChanged: false)
        }

        guard (200...299).contains(http.statusCode) else {
            throw FlagClientError.networkFailure(statusCode: http.statusCode, message: "")
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        let fgx: FGXResponse
        do {
            fgx = try ResponseParser.parseFGXResponse(body)
        } catch let error as ResponseParseException {
            throw FlagClientError.operationFailed(message: "Failed to parse features response", underlying: error)
        }
        return FlagApiResponse(fgxResponse: fgx,
                               etag: responseEtag,
                               isChanged: true)
    }

    /// Internal for unit tests.
    internal func buildFeatureRequestURL(clientId: String, contextVersion: String?) throws -> URL {
        let trimmedClientId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientId.isEmpty else {
            throw FlagClientError.invalidArgument(message: "clientId must not be null or blank")
        }

        var components = URLComponents(string: edgeBaseUrl + FlagConstants.FLAGS_FEATURE_PATH)
        guard components != nil else {
            throw FlagClientError.invalidArgument(message: "Invalid features URL")
        }

        var queryItems = [
            URLQueryItem(name: FlagConstants.Query.CLIENT_ID, value: trimmedClientId)
        ]

        queryItems.append(URLQueryItem(name: FlagConstants.Query.SDK_VERSION,
                                       value: (sdkVersion?.isEmpty == false) ? sdkVersion : nil))

        if let contextVersion = contextVersion, !contextVersion.isEmpty {
            queryItems.append(URLQueryItem(name: FlagConstants.Query.CONTEXT_VERSION, value: contextVersion))
        }

        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw FlagClientError.invalidArgument(message: "Invalid features URL")
        }
        return url
    }

    // MARK: - Synchronous transport (iOS 12 — no async/await)

    /// Case-insensitive header lookup (iOS 12–compatible).
    private static func headerValue(_ response: HTTPURLResponse, field: String) -> String? {
        for (key, value) in response.allHeaderFields {
            guard let keyStr = key as? String else { continue }
            if keyStr.caseInsensitiveCompare(field) == .orderedSame {
                return value as? String
            }
        }
        return nil
    }

    private func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var outData: Data?
        var outResponse: URLResponse?
        var outError: Error?

        let task = urlSession.dataTask(with: request) { data, response, error in
            outData = data
            outResponse = response
            outError = error
            semaphore.signal()
        }
        task.resume()

        let waitTimeout = FlagConstants.HTTP.READ_TIMEOUT_SECONDS + FlagConstants.HTTP.SEMAPHORE_SAFETY_MARGIN_SECONDS
        if semaphore.wait(timeout: .now() + waitTimeout) == .timedOut {
            task.cancel()
            throw FlagClientError.operationFailed(message: "Request timed out", underlying: nil)
        }

        if let error = outError {
            throw FlagClientError.operationFailed(message: "Features request failed", underlying: error)
        }
        guard let data = outData, let response = outResponse else {
            throw FlagClientError.operationFailed(message: "Empty response", underlying: nil)
        }
        return (data, response)
    }
}
