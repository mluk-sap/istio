#!/usr/bin/env bash

# Assemble release notes by walking git log since the given tag and extracting
# ```release-note blocks from merged PR descriptions.
#
# Usage:
#   assemble-release-notes.sh <since_tag> [--output <file>]
#
# <since_tag>  the tag to start from (exclusive)
# --output     write to file instead of stdout
#
# Requires: gh, git, jq, GITHUB_TOKEN in env.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_positional since_tag "$1"
shift

require_vars GITHUB_TOKEN
require_tools gh git jq

output_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output_file="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Read MINOR_VERSION — used for the output header.
root="${script_dir}/../.."
minor_version=""
if [ -f "${root}/MINOR_VERSION" ]; then
  minor_version="$(cat "${root}/MINOR_VERSION")"
fi

echo "Assembling release notes since ${since_tag}..." >&2

# Sections accumulate bullet lines.
declare -A sections
sections["features"]=""
sections["other_changes"]=""
sections["bug_fixes"]=""
sections["istio_upgrades"]=""
sections["security_updates"]=""
sections["dependency_updates"]=""

append_to_section() {
  local key="$1" line="$2"
  if [ -n "${sections[${key}]}" ]; then
    sections["${key}"]="${sections[${key}]}
${line}"
  else
    sections["${key}"]="${line}"
  fi
}

# Extract text between ```release-note and ``` fences.
# Outputs trimmed block content, or empty string if absent/empty.
extract_release_note_block() {
  echo "$1" | awk '/^```release-note/{found=1; next} found && /^```/{exit} found{print}' \
    | sed '/^[[:space:]]*$/d'
}

declare -A seen_prs

while IFS= read -r log_line; do
  pr_number=""
  if [[ "${log_line}" =~ \(#([0-9]+)\)$ ]]; then
    pr_number="${BASH_REMATCH[1]}"
  elif [[ "${log_line}" =~ pull\ request\ #([0-9]+) ]]; then
    pr_number="${BASH_REMATCH[1]}"
  fi
  [ -n "${pr_number}" ] || continue
  [ -z "${seen_prs[${pr_number}]+x}" ] || continue
  seen_prs["${pr_number}"]=1

  echo "Analyzing commit: ${log_line}" >&2

  pr_json=$(gh pr view "${pr_number}" --json title,body,labels 2>/dev/null) || {
    echo "  -> Warning: could not fetch PR #${pr_number}, skipping" >&2
    continue
  }

  pr_title=$(echo "${pr_json}" | jq -r '.title')
  pr_body=$(echo "${pr_json}"  | jq -r '.body // ""')
  pr_labels=$(echo "${pr_json}" | jq -r '[.labels[].name] | join(",")')

  block="$(extract_release_note_block "${pr_body}")"
  note_line="- ${pr_title} (#${pr_number})"

  if [ -n "${block}" ]; then
    note_line="- $(echo "${block}" | head -1)"
    rest="$(echo "${block}" | tail -n +2)"
    if [ -n "${rest}" ]; then
      note_line="${note_line}
$(echo "${rest}" | sed 's/^/  /')"
    fi
    note_line="${note_line} (#${pr_number})"

    if echo "${pr_labels}" | grep -qE "(^|,)kind/bug(,|$)"; then
      append_to_section "bug_fixes" "${note_line}"
      echo "  -> Taking explicit release note, routing to Bug Fixes" >&2
    elif echo "${pr_labels}" | grep -qE "(^|,)kind/istio-upgrade(,|$)"; then
      append_to_section "istio_upgrades" "${note_line}"
      echo "  -> Taking explicit release note, routing to Upstream Updates" >&2
    elif echo "${pr_labels}" | grep -qE "(^|,)kind/feature(,|$)"; then
      append_to_section "features" "${note_line}"
      echo "  -> Taking explicit release note, routing to New Features" >&2
    else
      append_to_section "other_changes" "${note_line}"
      echo "  -> Taking explicit release note, routing to Other Changes" >&2
    fi
  elif echo "${pr_labels}" | grep -qE "(^|,)kind/istio-upgrade(,|$)"; then
    append_to_section "istio_upgrades" "${note_line}"
    echo "  -> Generating release note from PR title, routing to Upstream Updates" >&2
  elif echo "${pr_labels}" | grep -qE "(^|,)dependencies(,|$)"; then
    if echo "${pr_labels}" | grep -qE "(^|,)security(,|$)"; then
      append_to_section "security_updates" "${note_line}"
      echo "  -> Generating release note from PR title, routing to Security Updates" >&2
    else
      append_to_section "dependency_updates" "${note_line}"
      echo "  -> Generating release note from PR title, routing to Dependency Updates" >&2
    fi
  else
    echo "  -> Skipping: no release-note block and no auto-generate label" >&2
  fi

done < <(git log --oneline "${since_tag}..HEAD")

# Determine upcoming version label for the header.
if [ -n "${minor_version}" ]; then
  version_label="${minor_version}"
else
  branch="$(git rev-parse --abbrev-ref HEAD)"
  version_label="${branch}"
fi

output=""
output+="# Release notes for upcoming ${version_label}
"

if [ -n "${sections[features]}" ]; then
  output+="
## New Features
${sections[features]}
"
fi

if [ -n "${sections[other_changes]}" ]; then
  output+="
## Other Changes
${sections[other_changes]}
"
fi

if [ -n "${sections[bug_fixes]}" ]; then
  output+="
## Bug Fixes
${sections[bug_fixes]}
"
fi

if [ -n "${sections[istio_upgrades]}" ]; then
  output+="
## Upstream Updates
${sections[istio_upgrades]}
"
fi

if [ -n "${sections[security_updates]}" ]; then
  output+="
## Security Updates
${sections[security_updates]}
"
fi

if [ -n "${sections[dependency_updates]}" ]; then
  output+="
## Dependency Updates
${sections[dependency_updates]}
"
fi

if [ -z "${sections[features]}${sections[other_changes]}${sections[bug_fixes]}${sections[istio_upgrades]}${sections[security_updates]}${sections[dependency_updates]}" ]; then
  output+="
No user-facing changes since ${since_tag}.
"
fi

if [ -n "${output_file}" ]; then
  printf '%s' "${output}" > "${output_file}"
  echo "Release notes written to ${output_file}" >&2
else
  printf '%s' "${output}"
fi
