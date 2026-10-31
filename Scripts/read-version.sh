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
# Resolves the Flags iOS extension version string for release scripts and CI.
# Priority: FLAGS_EXTENSION_VERSION env -> FlagConstants.extensionVersion (the single source of truth).
# Git tags are intentionally NOT consulted: they are created FROM this version at release time, may not be
# reachable from HEAD, and the old 'v*' glob never matched this repo's unprefixed tags (e.g. 5.0.0-beta).
# Fails (non-zero) if the version cannot be resolved or is not a valid version.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=Scripts/semver.sh
source "${ROOT}/Scripts/semver.sh"

if [[ -n "${FLAGS_EXTENSION_VERSION:-}" ]]; then
  VERSION="${FLAGS_EXTENSION_VERSION}"
else
  CONSTANTS="${ROOT}/AEPFlags/Sources/FlagConstants.swift"
  VERSION=""
  [[ -f "${CONSTANTS}" ]] && VERSION="$(read_source_version "${CONSTANTS}")"
fi

if [[ -z "${VERSION}" ]]; then
  echo "error: could not resolve extension version (set FLAGS_EXTENSION_VERSION or fix FlagConstants.extensionVersion)" >&2
  exit 1
fi

require_valid_version "${VERSION}"
printf '%s' "${VERSION}"
