#!/usr/bin/env bash

# Prints the previous release tag.
#
# Usage:
#   get-previous-release-tag.sh <release_tag>
#   get-previous-release-tag.sh
#
# With <release_tag>: finds the highest tag strictly before <release_tag>.
#   patch (X.Y.Z, Z>0): highest X.Y.* tag, excluding <release_tag> itself so the
#     script is idempotent — re-running after the tag already exists returns the same result.
#   minor (X.Y.0, Y>0): highest X.(Y-1).* tag.
#   major (X.0.0):      highest (X-1).*.* tag.
#
# Without argument: reads MINOR_VERSION from the repo root and walks backwards
#   through minors until a tag is found. Handles main branch (MINOR_VERSION points
#   to an unreleased minor with no tags yet) and release branches before first tag.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_tools git

all_tags=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)
echo "Found $(echo "${all_tags}" | grep -c . || true) release tag(s) in total" >&2

find_latest_tag_for_minor() {
  local major="$1" minor="$2"
  local matches tag
  echo "Looking for latest ${major}.${minor}.* tag..." >&2
  matches=$(echo "${all_tags}" | grep -E "^${major}\.${minor}\.[0-9]+$" || true)
  tag=$(echo "${matches}" | sort -V | tail -1)
  echo "${tag}"
}

find_latest_tag_for_major() {
  local major="$1"
  local matches tag
  echo "Looking for latest ${major}.*.* tag..." >&2
  matches=$(echo "${all_tags}" | grep -E "^${major}\." || true)
  tag=$(echo "${matches}" | sort -V | tail -1)
  echo "${tag}"
}

if [ -n "${1:-}" ]; then
  release_tag="$1"
  major=$(echo "${release_tag}" | cut -d. -f1)
  minor=$(echo "${release_tag}" | cut -d. -f2)
  patch=$(echo "${release_tag}" | cut -d. -f3)
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
else
  root="${script_dir}/../.."
  minor_version="$(cat "${root}/MINOR_VERSION")"
  major="${minor_version%%.*}"
  minor="${minor_version##*.}"
  echo "No release tag given — reading MINOR_VERSION (${minor_version}), walking backwards from ${major}.${minor}..." >&2

  previous=""
  while [ "${minor}" -ge 0 ]; do
    previous=$(find_latest_tag_for_minor "${major}" "${minor}")
    if [ -n "${previous}" ]; then
      break
    fi
    minor=$(( minor - 1 ))
  done
fi

if [ -z "${previous}" ]; then
  echo "ERROR: No previous release tag found" >&2
  exit 1
fi

echo "Previous release tag: ${previous}" >&2
echo "${previous}"
