#!/usr/bin/env bash
# Compute the next patch version for this repo.
# Reads major.minor from MINOR_VERSION in the repo root.
# Prints: X.Y.(N+1) based on the highest published GitHub release.
# Requires: gh CLI, GITHUB_TOKEN env var

set -euo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_tools gh jq

repo_root="${script_dir}/../.."
IFS='.' read -r major minor < "${repo_root}/MINOR_VERSION"

repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)

echo "Querying releases for ${major}.${minor}.* in ${repository}" >&2
highest_patch=$(gh api --paginate "repos/${repository}/releases" \
  | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
  | grep -E "^${major}\.${minor}\.[0-9]+$" \
  | sort -V \
  | tail -1)

if [[ -z "${highest_patch}" ]]; then
  echo "No existing releases for ${major}.${minor}.* — starting at ${major}.${minor}.0" >&2
  echo "${major}.${minor}.0"
  exit 0
fi

current_patch=$(echo "${highest_patch}" | cut -d. -f3)
next_patch=$((current_patch + 1))
echo "${major}.${minor}.${next_patch}"
