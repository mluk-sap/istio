#!/usr/bin/env bash

# Assemble release notes by walking git log since the given tag and extracting
# ```release-note blocks from merged PR descriptions.
#
# Usage:
#   assemble-release-notes.sh <output_file> <since_tag> <until>
#
# <output_file> file to write the release notes to
# <since_tag>   the tag to start from (exclusive)
# <until>       commit/tag to end at (inclusive), use HEAD for latest
#
# Requires: gh, git, jq, GITHUB_TOKEN in env.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_positional output_file "$1"
require_positional since_tag "$2"
require_positional until_ref "$3"

require_vars GITHUB_TOKEN
require_tools gh git jq

echo "Assembling release notes since ${since_tag}..."
repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Repository: ${repository}"

# Sections accumulate bullet lines.
# section_order defines display order; section_titles maps key -> heading.
section_order=("features" "bug_fixes" "istio_upgrades" "dependency_updates")
declare -A section_titles
section_titles["features"]="New Features"
section_titles["bug_fixes"]="Bug Fixes"
section_titles["istio_upgrades"]="Istio Updates"
section_titles["dependency_updates"]="Dependency Updates"
declare -A sections
for key in "${section_order[@]}"; do sections["${key}"]=""; done

any_release_notes=0

append_to_section() {
  local key="$1" line="$2"
  any_release_notes=1
  if [ -n "${sections[${key}]}" ]; then
    sections["${key}"]="${sections[${key}]}
${line}"
  else
    sections["${key}"]="${line}"
  fi
}

# Formats a multi-line block as a markdown bullet: first line prefixed with "- ",
# subsequent lines indented with two spaces.
format_bullet() {
  local first=1
  while IFS= read -r line; do
    if [ "${first}" -eq 1 ]; then
      echo "- ${line}"
      first=0
    else
      echo "  ${line}"
    fi
  done <<< "$1"
}

# Extract text between ```release-note and ``` fences.
# Outputs trimmed block content, or empty string if absent/empty.
extract_release_note_block() {
  echo "$1" | tr -d '\r' | awk '/^```release-note/{found=1; next} found && /^```/{exit} found{print}' \
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

  echo "Analyzing commit: ${log_line}"
  pr_json=$(gh pr view "${pr_number}" --json title,body,labels 2>/dev/null) || {
    echo "  Warning: could not fetch PR #${pr_number}, skipping"
    continue
  }

  pr_title=$(echo "${pr_json}" | jq -r '.title')
  pr_body=$(echo "${pr_json}"  | jq -r '.body // ""')
  pr_labels=$(echo "${pr_json}" | jq -r '[.labels[].name] | join(",")')

  block="$(extract_release_note_block "${pr_body}")"
  pr_link="See [#${pr_number}](https://github.com/${repository}/pull/${pr_number})"
  note_line="$(format_bullet "${pr_title}") ${pr_link}"

  if [ -n "${block}" ]; then
    note_line="$(format_bullet "${block}") ${pr_link}"

    if echo "${pr_labels}" | grep -qE "(^|,)kind/bug(,|$)"; then
      append_to_section "bug_fixes" "${note_line}"
      echo "  Routing to Bug Fixes"
    elif echo "${pr_labels}" | grep -qE "(^|,)kind/istio-upgrade(,|$)"; then
      append_to_section "istio_upgrades" "${note_line}"
      echo "  Routing to Istio Updates"
    elif echo "${pr_labels}" | grep -qE "(^|,)kind/feature(,|$)"; then
      append_to_section "features" "${note_line}"
      echo "  Routing to New Features"
    else
      echo "  Skipping: explicit release note but no matching label (kind/bug, kind/feature, kind/istio-upgrade)"
    fi
  elif echo "${pr_labels}" | grep -qE "(^|,)kind/istio-upgrade(,|$)"; then
    append_to_section "istio_upgrades" "${note_line}"
    echo "  Routing to Istio Updates (auto-generated from label)"
  elif echo "${pr_labels}" | grep -qE "(^|,)dependencies(,|$)"; then
    append_to_section "dependency_updates" "${note_line}"
    echo "  Routing to Dependency Updates (auto-generated from label)"
  else
    echo "  Skipping: no release-note block and no auto-generate label"
  fi

done < <(git log --oneline "${since_tag}..${until_ref}")

# If no section has content, fall back to a generic dependency update notice.
if [ "${any_release_notes}" -eq 0 ]; then
  echo "No explicit release notes found — using generic fallback"
  sections["dependency_updates"]="This version includes dependency updates and security patches."
fi

output=""
for key in "${section_order[@]}"; do
  if [ -n "${sections[${key}]}" ]; then
    output+=$(printf '\n## %s\n\n%s\n' "${section_titles[${key}]}" "${sections[${key}]}")
  fi
done

printf '%s' "${output}" > "${output_file}"
echo "Release notes written to ${output_file}"