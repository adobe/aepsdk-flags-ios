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
#
# Run AEPFlagsTests and FlagsEngineTests on an iOS Simulator via Swift Package Manager.
# FlagsEngine is a local source target (see Package.swift) -- no CDN binary pin, no
# framework-embedding workaround needed; SPM links and packages everything automatically.
#
# AEPFlagsTests never touches the real AEPCore MobileCore EventHub (extension behavior is tested
# against a mock ExtensionRuntime -- see AEPFlags/Tests/UnitTests/TestHelpers/TestableExtensionRuntime.swift),
# so there is no EventHub-shutdown timing race to retry around here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

swift package resolve

DEST="$("./Scripts/resolve_ios_sim_dest.sh" "${1:-${DEST:-}}")"
DD="${ROOT}/.build/DerivedData"

xcodebuild build-for-testing \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -derivedDataPath "${DD}"

xcodebuild test-without-building \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -only-testing:AEPFlagsTests \
  -parallel-testing-enabled NO \
  -derivedDataPath "${DD}"

xcodebuild test-without-building \
  -scheme AEPFlags \
  -destination "${DEST}" \
  -only-testing:FlagsEngineTests \
  -parallel-testing-enabled NO \
  -derivedDataPath "${DD}"
