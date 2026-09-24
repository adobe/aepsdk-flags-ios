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

@objc public extension Flag {

    /// Create and initialize a client synchronously.
    /// Creates a Flag client synchronously.
    @objc(createWithConfiguration:error:)
    static func create(configuration: FlagConfiguration) throws -> Flag {
        let client = Flag(configuration: configuration)
        do {
            try client.initialize()
            return client
        } catch {
            client.close()
            throw FlagInitError.initializationFailed(message: "Failed to initialize FlagClient", underlying: error)
        }
    }

    /// Create and initialize a client asynchronously.
    /// Completion is invoked on `queue` (defaults to a dedicated background queue).
    /// Creates a Flag client asynchronously.
    @objc(createAsyncWithConfiguration:queue:completion:)
    static func createAsync(configuration: FlagConfiguration,
                            queue: DispatchQueue? = nil,
                            completion: @escaping (Flag?, Error?) -> Void) {
        let runQueue = queue ?? DispatchQueue(label: "com.adobe.marketing.flags.init-\(configuration.clientId)")
        runQueue.async {
            do {
                let client = try create(configuration: configuration)
                completion(client, nil)
            } catch {
                completion(nil, error)
            }
        }
    }

    ///  completes with `FlagInitError.missingConfiguration`.
    /// Swift-only: cannot share the same Objective-C selector as ``createAsync(configuration:queue:completion:)``.
    @nonobjc
    static func createAsync(configuration: FlagConfiguration?,
                            queue: DispatchQueue? = nil,
                            completion: @escaping (Flag?, Error?) -> Void) {
        guard let configuration = configuration else {
            let runQueue = queue ?? DispatchQueue(label: "com.adobe.marketing.flags.init-null-config")
            runQueue.async {
                completion(nil, FlagInitError.missingConfiguration)
            }
            return
        }
        createAsync(configuration: configuration, queue: queue, completion: completion)
    }

    ///  null work queue is rejected.
    static func createAsync(configuration: FlagConfiguration,
                            requiringWorkQueue workQueue: DispatchQueue?,
                            completion: @escaping (Flag?, Error?) -> Void) {
        guard let workQueue = workQueue else {
            let runQueue = DispatchQueue(label: "com.adobe.marketing.flags.null-work-queue")
            runQueue.async {
                completion(nil, FlagInitError.initializationFailed(
                    message: "Failed to initialize FlagClient",
                    underlying: FlagClientError.invalidArgument(message: "Executor is required")))
            }
            return
        }
        createAsync(configuration: configuration, queue: workQueue, completion: completion)
    }

    /// `true` if this client is initialized and not yet closed.
    var isInitialized: Bool {
        return stateQueue.sync { _initialized && !_closed }
    }

    /// Release all resources held by this client. Safe to call multiple times.
    func close() {
        let shouldShutdown: Bool = stateQueue.sync {
            if _closed { return false }
            _closed = true
            _initialized = false
            return true
        }
        if shouldShutdown {
            shutdown()
        }
    }
}
