#!/usr/bin/env bash
# Prints the two latest release-X.Y branches for this repo (semver sort).
# Must be run from a full checkout (fetch-depth: 0).
# Requires: gh CLI, GITHUB_TOKEN env var

set -euo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_tools gh jq

repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)

gh api --paginate "repos/${repository}/branches" \
  | jq -r '.[].name' \
  | grep -E '^release-[0-9]+\.[0-9]+$' \
  | sort -t'-' -k2 -V \
  | tail -2
