#!/usr/bin/env bash

# Prints the last released semver tag, optionally scoped to a minor version.
#
# Usage: get-last-release-tag.sh [<minor_version>]
#
# With <minor_version> (e.g. "1.34"): returns the highest X.Y.Z tag for that minor.
# Without argument: returns the highest X.Y.Z tag across all versions.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_tools git

minor_version="${1:-}"

if [ -n "${minor_version}" ]; then
  tag="$(git tag --list | grep -E "^${minor_version//./\\.}\.[0-9]+$" | sort -V | tail -1)"
else
  tag="$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
fi

[ -n "${tag}" ] || { echo "No release tag found${minor_version:+ for minor ${minor_version}}" >&2; exit 1; }
echo "${tag}"
