#!/usr/bin/env bash

# Integration test for assemble-release-notes.sh.
# Creates several PRs with different labels and release note blocks, merges them,
# then runs assemble-release-notes.sh and prints the result.
#
# Usage: test-assemble-release-notes.sh
#
# Requires: gh, git, GITHUB_TOKEN in env.
# Must be run from the root of the repository on a fork where you have push access.

set -eo pipefail
script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${script_dir}/common.sh"

require_vars GITHUB_TOKEN
require_tools gh git

repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)
default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
echo "Repository: ${repository}, default branch: ${default_branch}"

# Record the current HEAD so we can use it as the since point.
base_sha=$(git rev-parse HEAD)
echo "Base SHA: ${base_sha}"

create_and_merge_pr() {
  local branch="$1"
  local title="$2"
  local labels="$3"
  local body="$4"

  echo ""
  echo "=== Creating PR: ${title} ==="

  git checkout "${default_branch}"
  git branch -D "${branch}" 2>/dev/null || true
  git push origin --delete "${branch}" 2>/dev/null || true
  git checkout -b "${branch}"
  # Make a trivial commit so the branch differs from base.
  echo "${branch}" >> /tmp/test-rn-marker.txt
  git add /tmp/test-rn-marker.txt 2>/dev/null || true
  # Touch a unique file per branch to avoid conflicts.
  touch "hack/ci/.test-rn-${branch}"
  git add "hack/ci/.test-rn-${branch}"
  git commit -m "${title}"
  git push origin "${branch}"

  pr_url=$(gh pr create \
    --title "${title}" \
    --body "${body}" \
    --base "${default_branch}" \
    --head "${branch}" \
    --repo "${repository}")
  pr_number=$(echo "${pr_url}" | grep -oE '[0-9]+$')
  echo "Created PR #${pr_number}"

  # Apply labels.
  if [ -n "${labels}" ]; then
    IFS=',' read -ra label_arr <<< "${labels}"
    for label in "${label_arr[@]}"; do
      gh pr edit "${pr_number}" --add-label "${label}" --repo "${repository}" 2>/dev/null || \
        echo "  Warning: could not add label '${label}' (may not exist)"
    done
  fi

  gh pr merge "${pr_number}" --squash --repo "${repository}"
  echo "Merged PR #${pr_number}"

  git checkout "${default_branch}"
  git pull origin "${default_branch}"
  git branch -D "${branch}" 2>/dev/null || true
}

# --- PR 1: feature with single-line release note ---
create_and_merge_pr \
  "test-rn-feature-1" \
  "feat: add support for custom timeout configuration" \
  "kind/feature" \
  "**Description**

Adds a new timeout field to the Istio CR.

\`\`\`release-note
You can now configure custom timeout values in the Istio CR via the \`spec.config.timeout\` field.
\`\`\`

**Related issues**
"

# --- PR 2: bug fix with multiline release note ---
create_and_merge_pr \
  "test-rn-bugfix-1" \
  "fix: correct proxy sidecar injection for namespaces with special characters" \
  "kind/bug" \
  "**Description**

Fixes a crash in sidecar injection.

\`\`\`release-note
Fixed a crash in proxy sidecar injection that occurred when namespace names contained
special characters such as dots or underscores.
Affected versions: 1.33.0 and later.
\`\`\`

**Related issues**
"

# --- PR 3: Istio upgrade (no release note block, auto-generated from label) ---
create_and_merge_pr \
  "test-rn-istio-upgrade-1" \
  "chore: upgrade Istio to 1.34.1" \
  "kind/istio-upgrade" \
  "## Automated Istio version upgrade

- Istio version: \`1.34.1\`
- Istio changelog: https://istio.io/latest/news/releases/1.34.x/announcing-1.34.1/
"

# --- PR 4: dependency bump (no release note block, auto-generated from label) ---
create_and_merge_pr \
  "test-rn-deps-1" \
  "chore: bump golang.org/x/net to v0.26.0" \
  "dependencies" \
  "Automated dependency update by Dependabot.
"

# --- PR 5: feature with multiline release note (3 lines) ---
create_and_merge_pr \
  "test-rn-feature-2" \
  "feat: add experimental ambient mesh support" \
  "kind/feature" \
  "**Description**

Introduces ambient mesh mode as an experimental feature.

\`\`\`release-note
Experimental ambient mesh support is now available.
Enable it by setting \`spec.config.experimental.ambientMeshEnabled: true\` in the Istio CR.
Note: this feature is not recommended for production use.
\`\`\`

**Related issues**
"

# --- PR 6: no labels, no release note — should be skipped ---
create_and_merge_pr \
  "test-rn-skip-1" \
  "refactor: clean up internal reconciler logic" \
  "" \
  "Internal refactoring, no user-facing changes.
"

# --- PR 7: has release note block but no matching label — should be skipped ---
create_and_merge_pr \
  "test-rn-skip-2" \
  "docs: update contributing guide" \
  "" \
  "\`\`\`release-note
Updated the contributing guide with new PR checklist items.
\`\`\`
"

echo ""
echo "=== All PRs created and merged. Running assemble-release-notes.sh ==="
echo ""

# Pull latest to make sure we have all merged commits.
git pull origin "${default_branch}"

output_file=$(mktemp)
"${script_dir}/assemble-release-notes.sh" "${output_file}" "${base_sha}" HEAD

echo "=== Release Notes Output ==="
cat "${output_file}"

echo ""
echo "=== Cleaning up test marker files ==="
git rm -f hack/ci/.test-rn-* 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "chore: clean up release notes test files [skip ci]"
  git push origin "${default_branch}"
fi
