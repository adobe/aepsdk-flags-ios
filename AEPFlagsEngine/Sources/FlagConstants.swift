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

/// SDK constants — service endpoints, headers, configuration values, and JSON keys.
/// Internal SDK use only.
enum FlagConstants {

    static let LOG_TAG = "AEPFlags"
    static let EXTENSION_NAME = "com.adobe.marketing.flags"
    static let FRIENDLY_NAME = "Flags"

    static let HTTPS_SCHEME = "https://"
    static let FLAGS_FEATURE_PATH = "/flags/feature"
    static let URL_PATH_SEPARATOR = "/"

    enum Headers {
        static let ACCEPT = "Accept"
        static let IMS_ORG = "x-gw-ims-org-id"
        static let SANDBOX_NAME = "x-sandbox-name"
        static let ETAG = "ETag"
        static let IF_NONE_MATCH = "If-None-Match"
        static let ACCEPT_JSON = "application/json"
    }

    enum Query {
        static let CLIENT_ID = "clientId"
        static let SDK_VERSION = "sdkVersion"
        static let CONTEXT_VERSION = "contextVersion"
    }

    enum Cache {
        static let DEFAULT_POLL_INTERVAL_SECONDS = 300
        static let DEFAULT_MAX_RETRY_ATTEMPTS = 3
        static let DEFAULT_RETRY_DELAY_MS: Int64 = 1_000
        static let MAX_RETRY_DELAY_MS: Int64 = 30_000
    }

    enum HTTP {
        static let CONNECT_TIMEOUT_SECONDS: TimeInterval = 10
        static let READ_TIMEOUT_SECONDS: TimeInterval = 30
        static let WRITE_TIMEOUT_SECONDS: TimeInterval = 30
        /// Extra buffer added to `READ_TIMEOUT_SECONDS` for the semaphore safety net in
        /// `APIProxy.perform(_:)`. Allows the URLSession timeout to fire first under
        /// normal conditions while still guarding against a callback that never arrives.
        static let SEMAPHORE_SAFETY_MARGIN_SECONDS: TimeInterval = 30
    }

    enum Policy {
        static let CONTROL_GROUP_VARIANT_ID = "0"
        static let CONTROL_GROUP_FEATURE_ID = -1
        static let DEFAULT_COHORTING_NAMESPACE = "ECID"
    }

    enum IdentityMap {
        static let ENTRY_KEY_ID = "id"
        static let ENTRY_KEY_PRIMARY = "primary"
        static let ENTRY_KEY_AUTHENTICATED_STATE = "authenticatedState"
    }

    enum JSONKeys {
        static let VERSION = "v"
        static let FEATURE_GROUPS = "featureGroups"
        static let FEATURES = "features"
        static let KEY = "key"
        static let TTL = "ttl"
        static let CONTEXT_VERSION = "contextVersion"
        static let CONTEXTS = "contexts"
        static let COHORTING_TYPE = "cohortingType"
        static let COHORTING_NAMESPACE_CODE = "cohortingNamespaceCode"
        static let PARAMS = "params"
        static let CRITERIA = "criteria"
        static let POLICY_ID = "policyId"
        static let HASH = "hash"
        static let HASH_ALGORITHM = "hashAlgorithm"
        static let BUCKETS = "buckets"
        static let META = "meta"
        static let ANALYTICS_ENABLED = "analyticsEnabled"
    }
}
