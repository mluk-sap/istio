#!/usr/bin/env bash

# Prints the previous release tag.
#
# Usage:
#   get-previous-release-tag.sh <release_tag>
#   get-previous-release-tag.sh
#
# With <release_tag>: finds the highest tag strictly before <release_tag>.
#   patch (X.Y.Z, Z>0): highest X.Y.* tag, excluding <release_tag> itself so the
#     script is idempotent when the tag already exists (e.g. on workflow retry).
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

if [ -n "${1:-}" ]; then
  release_tag="$1"
  major=$(echo "${release_tag}" | cut -d. -f1)
  minor=$(echo "${release_tag}" | cut -d. -f2)
  patch=$(echo "${release_tag}" | cut -d. -f3)

  if [ "${patch}" -ne 0 ]; then
    previous=$(echo "${all_tags}" | grep -E "^${major}\.${minor}\." | grep -v "^${release_tag}$" | tail -1)
  elif [ "${minor}" -ne 0 ]; then
    prev_minor=$((minor - 1))
    previous=$(echo "${all_tags}" | grep -E "^${major}\.${prev_minor}\." | tail -1)
  else
    prev_major=$((major - 1))
    previous=$(echo "${all_tags}" | grep -E "^${prev_major}\." | tail -1)
  fi
else
  root="${script_dir}/../.."
  minor_version="$(cat "${root}/MINOR_VERSION")"
  major="${minor_version%%.*}"
  minor="${minor_version##*.}"

  echo "No release tag given — reading MINOR_VERSION (${minor_version}), walking backwards..." >&2
  previous=""
  while [ "${minor}" -ge 0 ]; do
    previous=$(echo "${all_tags}" | grep -E "^${major}\.${minor}\." | tail -1)
    if [ -n "${previous}" ]; then
      break
    fi
    minor=$(( minor - 1 ))
  done
fi

[ -n "${previous}" ] || { echo "No previous release tag found (MINOR_VERSION=${minor_version:-}, searched back from ${major}.${minor_version##*.})" >&2; exit 1; }
echo "${previous}"
