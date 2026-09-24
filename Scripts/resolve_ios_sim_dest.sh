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
# Print an xcodebuild -destination value for an available iPhone simulator.
# Prefers common device names (portable across Xcode versions), then any iPhone.
set -euo pipefail

if [[ $# -gt 0 && -n "${1}" ]]; then
  echo "${1}"
  exit 0
fi

available="$(xcrun simctl list devices available 2>/dev/null || true)"

for name in "iPhone 15" "iPhone 16" "iPhone 17" "iPhone 14" "iPhone 15 Pro" "iPhone 16 Pro"; do
  if echo "${available}" | grep -qF " ${name} ("; then
    echo "platform=iOS Simulator,name=${name}"
    exit 0
  fi
done

fallback="$(echo "${available}" | grep -E '^[[:space:]]+iPhone' | head -1 | sed -E 's/^[[:space:]]+([^([]+).*/\1/' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
if [[ -n "${fallback}" ]]; then
  echo "platform=iOS Simulator,name=${fallback}"
  exit 0
fi

echo "platform=iOS Simulator,name=iPhone 15" >&2
echo "warning: no available iPhone simulator found; defaulting to iPhone 15" >&2
echo "platform=iOS Simulator,name=iPhone 15"
