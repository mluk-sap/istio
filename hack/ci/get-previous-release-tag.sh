#!/usr/bin/env bash

# Prints the previous release tag for a given release tag.
# Used to build the GitHub compare URL in the release body.
#
# Usage: get-previous-release-tag.sh <release_tag>
#
# For a patch release (X.Y.Z, Z>0): previous tag is the highest X.Y.* tag strictly
#   less than <release_tag>. The release_tag itself is excluded so the script is
#   idempotent — re-running after the tag already exists returns the same result.
# For a minor release (X.Y.0, Y>0): previous tag is the highest X.(Y-1).* tag.
# For a major release (X.0.0):      previous tag is the highest (X-1).*.* tag.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_positional release_tag "$1"
require_tools git

major=$(echo "${release_tag}" | cut -d. -f1)
minor=$(echo "${release_tag}" | cut -d. -f2)
patch=$(echo "${release_tag}" | cut -d. -f3)

all_tags=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)

if [ "${patch}" -ne 0 ]; then
  # Exclude release_tag itself: if the tag was already created before this script
  # runs (e.g. on workflow retry), we must not return it as its own previous tag.
  previous=$(echo "${all_tags}" | grep -E "^${major}\.${minor}\." | grep -v "^${release_tag}$" | tail -1)
elif [ "${minor}" -ne 0 ]; then
  prev_minor=$((minor - 1))
  previous=$(echo "${all_tags}" | grep -E "^${major}\.${prev_minor}\." | tail -1)
else
  prev_major=$((major - 1))
  previous=$(echo "${all_tags}" | grep -E "^${prev_major}\." | tail -1)
fi

[ -n "${previous}" ] || { echo "No previous release tag found for ${release_tag}" >&2; exit 1; }
echo "${previous}"
