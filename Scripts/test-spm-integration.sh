#!/usr/bin/env bash
#
# Copyright 2026 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

# Verifies that a downstream Swift Package Manager consumer can resolve and compile
# against AEPFlags. Builds a throwaway package that depends on this repo via a local
# path dependency and imports the public API, compiled for the iOS simulator.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
IOS_SIM_TRIPLE="$(uname -m)-apple-ios12.0-simulator"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/Sources/SPMIntegration"

cat > "$TMP/Package.swift" <<EOF
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SPMIntegration",
    platforms: [.iOS(.v12)],
    dependencies: [
        .package(name: "AEPFlags", path: "$ROOT")
    ],
    targets: [
        .target(
            name: "SPMIntegration",
            dependencies: [
                .product(name: "AEPFlags", package: "AEPFlags")
            ]
        )
    ]
)
EOF

cat > "$TMP/Sources/SPMIntegration/Consume.swift" <<'EOF'
import AEPFlags

// Touch the public surface so the compiler must resolve and link AEPFlags.
enum SPMIntegrationSmoke {
    static let version = Flag.extensionVersion
    static func makeContext() -> FeatureEvaluationContext {
        FeatureEvaluationContext.builder().build()
    }
}
EOF

echo "==> Building SPM consumer against AEPFlags (local path dependency)"
cd "$TMP"
swift build --sdk "$IOS_SIM_SDK" --triple "$IOS_SIM_TRIPLE"
echo "==> SPM integration build succeeded"
