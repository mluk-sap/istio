#!/usr/bin/env bash

# Assemble release notes by walking git log since the given tag and extracting
# ```release-notes-* blocks from merged PR descriptions.
#
# Usage:
#   assemble-release-notes.sh <output_file> <since_tag> <until>
#
# <output_file> file to write the release notes to
# <since_tag>   the tag/commit to start from (exclusive)
# <until>       commit/tag to end at (inclusive), use HEAD for latest
#
# Section titles are derived from block names by stripping the "release-notes-"
# prefix, replacing hyphens with spaces, and capitalizing each word.
# Example: release-notes-new-features -> New Features
#
# Dependabot PRs (detected by "dependencies" label) are auto-added to the
# "Dependency Updates" section even without a release-notes block.
#
# Requires: gh, git, jq, GITHUB_TOKEN in env.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_positional output_file "$1"
require_positional since_tag "$2"
require_positional until_ref "$3"

require_vars GITHUB_TOKEN
require_tools gh git jq

echo "Assembling release notes since ${since_tag} until ${until_ref}..."

git rev-parse --verify "${since_tag}" > /dev/null
since_exit=$?
if [[ "${since_exit}" -ne 0 ]]; then
  echo "ERROR: since ref '${since_tag}' not found in git history" >&2
  exit 1
fi

git rev-parse --verify "${until_ref}" > /dev/null
until_exit=$?
if [[ "${until_exit}" -ne 0 ]]; then
  echo "ERROR: until ref '${until_ref}' not found in git history" >&2
  exit 1
fi

repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "Repository: ${repository}"

# Derives a section title from a block name.
# release-notes-new-features -> New Features
section_title_from_block_name() {
  local name="$1"
  local stripped="${name#release-notes-}"
  local spaced="${stripped//-/ }"
  echo "${spaced}" | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

# Extracts the content of all ```release-notes-* blocks from a PR body.
# Outputs lines in the format: "<block_name>:<content_line>"
extract_release_note_blocks() {
  local body="$1"
  echo "${body}" | tr -d '\r' | awk '
    /^```release-notes-[a-z]/ {
      block_name = substr($0, 4)
      # strip trailing whitespace
      gsub(/[[:space:]]+$/, "", block_name)
      found = 1
      next
    }
    found && /^```/ {
      found = 0
      block_name = ""
      next
    }
    found && /[^[:space:]]/ {
      print block_name ":" $0
    }
  '
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

# sections maps section_name -> accumulated bullet lines
# section_order tracks insertion order for deterministic output
declare -A sections
declare -a section_order

any_release_notes=0

append_to_section() {
  local section="$1" line="$2"
  any_release_notes=1
  if [ -z "${sections[${section}]+x}" ]; then
    section_order+=("${section}")
    sections["${section}"]="${line}"
  elif [ -n "${sections[${section}]}" ]; then
    sections["${section}"]="${sections[${section}]}
${line}"
  else
    sections["${section}"]="${line}"
  fi
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

  echo "Analyzing PR #${pr_number}: ${log_line}"

  pr_json=""
  if pr_json=$(gh pr view "${pr_number}" --json title,body,labels 2>/dev/null); then
    echo "  Found PR #${pr_number} in current repo"
  else
    upstream_repo=$(cat "${script_dir}/../../RELEASE_REPOSITORY")
    if [[ "${upstream_repo}" == "${repository}" ]]; then
      echo "  Warning: could not fetch PR #${pr_number}, skipping"
      continue
    fi
    echo "  PR #${pr_number} not found in current repo, trying upstream (${upstream_repo})"
    if pr_json=$(gh pr view "${pr_number}" --repo "${upstream_repo}" --json title,body,labels 2>/dev/null); then
      echo "  Found PR #${pr_number} in upstream repo"
    else
      echo "  Warning: could not fetch PR #${pr_number} from current repo or upstream, skipping"
      continue
    fi
  fi

  pr_title=$(echo "${pr_json}" | jq -r '.title')
  pr_body=$(echo "${pr_json}"  | jq -r '.body // ""')
  pr_labels=$(echo "${pr_json}" | jq -r '[.labels[].name] | join(",")')

  pr_link="See [#${pr_number}](https://github.com/${repository}/pull/${pr_number})"

  # Extract all release-notes-* blocks.
  blocks_found=0
  while IFS=: read -r block_name block_line; do
    [ -n "${block_name}" ] || continue
    blocks_found=1
    section=$(section_title_from_block_name "${block_name}")
    echo "  Found block '${block_name}' -> section '${section}'"
    # Accumulate lines for this block per PR, then format as bullet after loop.
    # We use a temp var keyed by pr_number+block_name.
    varkey="block_${pr_number}_${block_name//[^a-zA-Z0-9]/_}"
    if [ -z "${!varkey+x}" ]; then
      printf -v "${varkey}" '%s' "${block_line}"
    else
      printf -v "${varkey}" '%s\n%s' "${!varkey}" "${block_line}"
    fi
    # Track which (section, varkey) pairs we've seen for this PR.
    sections_for_pr="${sections_for_pr:-} ${section}:${varkey}"
  done < <(extract_release_note_blocks "${pr_body}")

  # Flush accumulated block content to sections.
  if [ "${blocks_found}" -eq 1 ]; then
    for entry in ${sections_for_pr:-}; do
      [ -n "${entry}" ] || continue
      section="${entry%%:*}"
      varkey="${entry#*:}"
      content="${!varkey}"
      note_line="$(format_bullet "${content}") ${pr_link}"
      append_to_section "${section}" "${note_line}"
    done
    sections_for_pr=""
  elif echo "${pr_labels}" | grep -qE "(^|,)dependencies(,|$)"; then
    # Dependabot/automated dependency PRs: auto-add to Dependency Updates.
    note_line="$(format_bullet "${pr_title}") ${pr_link}"
    append_to_section "Dependency Updates" "${note_line}"
    echo "  Routing to Dependency Updates (auto-generated from dependencies label)"
  else
    echo "  Skipping: no release-notes-* blocks and no dependencies label"
  fi

done < <(git log --oneline "${since_tag}..${until_ref}")

# If nothing was collected, fall back to a generic dependency update notice.
if [ "${any_release_notes}" -eq 0 ]; then
  echo "No release notes found — using generic fallback"
  append_to_section "Dependency Updates" "This version includes dependency updates and security patches."
fi

output=""
for section in "${section_order[@]}"; do
  output+=$(printf '\n## %s\n\n%s\n' "${section}" "${sections[${section}]}")
done

printf '%s' "${output}" > "${output_file}"
echo "Release notes written to ${output_file}"
