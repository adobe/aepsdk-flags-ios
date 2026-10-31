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
# Validate that the source product version matches an expected version (usually the release tag).
# The product version is single-sourced in AEPFlags/Sources/FlagConstants.swift `extensionVersion`.
# The version is defined only in FlagConstants.swift (SPM + XCFramework distribution only).
# Usage: sh ./Scripts/version.sh [<expected-version>]
#   With no argument, checks that every version carrier agrees with FlagConstants.extensionVersion.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/semver.sh
source "${ROOT}/Scripts/semver.sh"
CONSTANTS="${ROOT}/AEPFlags/Sources/FlagConstants.swift"
ENGINE_PLIST="${ROOT}/AEPFlagsEngine/Sources/Info.plist"

SOURCE_VERSION="$(read_source_version "${CONSTANTS}")"
if [[ -z "${SOURCE_VERSION}" ]]; then
  echo "[error] could not read extensionVersion from ${CONSTANTS}" >&2
  exit 1
fi

EXPECTED="${1:-${SOURCE_VERSION}}"
require_valid_version "${EXPECTED}"

if [[ "${EXPECTED}" != "${SOURCE_VERSION}" ]]; then
  echo "[error] Version mismatch: expected '${EXPECTED}' but FlagConstants.extensionVersion is '${SOURCE_VERSION}'." >&2
  echo "        Run the Update Version workflow (or Scripts/update-version.sh) to bump the source first." >&2
  exit 1
fi

# Every other place that carries the version must agree with the source of truth.
ENGINE_PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${ENGINE_PLIST}" 2>/dev/null || true)"
if [[ "${ENGINE_PLIST_VERSION}" != "${EXPECTED}" ]]; then
  echo "[error] ${ENGINE_PLIST#${ROOT}/} CFBundleShortVersionString is '${ENGINE_PLIST_VERSION}', expected '${EXPECTED}'." >&2
  echo "        Run the Update Version workflow (or Scripts/update-version.sh) to sync it." >&2
  exit 1
fi

echo "Pass! Version ${EXPECTED} matches FlagConstants.extensionVersion and all version carriers."
