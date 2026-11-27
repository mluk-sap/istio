#!/usr/bin/env bash

# Prints the previous release tag for a given release tag.
#
# Usage:
#   get-previous-release-tag.sh <release_tag>
#
# patch (X.Y.Z, Z>0): highest X.Y.* tag, excluding <release_tag> itself so the
#   script is idempotent — re-running after the tag already exists returns the same result.
# minor (X.Y.0, Y>0): highest X.(Y-1).* tag.
# major (X.0.0):      highest (X-1).*.* tag.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_tools git
require_positional release_tag "$1"

major=$(echo "${release_tag}" | cut -d. -f1)
minor=$(echo "${release_tag}" | cut -d. -f2)
patch=$(echo "${release_tag}" | cut -d. -f3)

all_tags=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)
echo "Found $(echo "${all_tags}" | grep -c . || true) release tag(s) in total" >&2

find_latest_tag_for_minor() {
  local major="$1" minor="$2"
  echo "Looking for latest ${major}.${minor}.* tag..." >&2
  echo "${all_tags}" | grep -E "^${major}\.${minor}\.[0-9]+$" | sort -V | tail -1 || true
}

find_latest_tag_for_major() {
  local major="$1"
  echo "Looking for latest ${major}.*.* tag..." >&2
  echo "${all_tags}" | grep -E "^${major}\." | sort -V | tail -1 || true
}

echo "Finding previous tag for ${release_tag}..." >&2

if [ "${patch}" -ne 0 ]; then
  # Exclude release_tag itself: if the tag was already created before this script
  # runs (e.g. on workflow retry), we must not return it as its own previous tag.
  all_tags=$(echo "${all_tags}" | grep -v "^${release_tag}$" || true)
  previous=$(find_latest_tag_for_minor "${major}" "${minor}")
elif [ "${minor}" -ne 0 ]; then
  prev_minor=$((minor - 1))
  previous=$(find_latest_tag_for_minor "${major}" "${prev_minor}")
else
  prev_major=$((major - 1))
  previous=$(find_latest_tag_for_major "${prev_major}")
fi

if [ -z "${previous}" ]; then
  echo "ERROR: No previous release tag found" >&2
  exit 1
fi

echo "Previous release tag: ${previous}" >&2
echo "${previous}"
