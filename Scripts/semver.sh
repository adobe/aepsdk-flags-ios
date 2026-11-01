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
# Shared helpers for the version scripts (source this file; do not execute it).
#
# Tag convention for this repo: the git tag IS the version, with NO "v" prefix.
# The single source of truth for the version is AEPFlags/Sources/FlagConstants.swift `extensionVersion`.
# Keep SEMVER_RE identical to the regex in AEPFlags/Tests/UnitTests/FlagConstantsTests.swift.

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$'

# Exits non-zero with a clear message when $1 is not X.Y.Z or X.Y.Z-suffix (a "v" prefix is rejected).
require_valid_version() {
  local v="${1:-}"
  if ! [[ "${v}" =~ ${SEMVER_RE} ]]; then
    echo "[error] '${v}' is not a valid version. Use X.Y.Z or X.Y.Z-suffix with no 'v' prefix." >&2
    return 1
  fi
}

# Prints the version declared in FlagConstants.swift (empty if not found).
read_source_version() {
  sed -n 's/.*extensionVersion[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1
}
