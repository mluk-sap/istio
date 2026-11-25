#!/usr/bin/env bash

# Creates or updates a draft GitHub release with assembled release notes.
#
# Usage: create-draft-release.sh <release_tag> <release_id_output_file>

set -eo pipefail
script_dir="$(dirname "$(readlink -f "$0")")"
# shellcheck source=./common.sh
source "${script_dir}/common.sh"

require_positional release_tag "$1"
require_positional release_id_output_file "$2"
require_vars GITHUB_TOKEN
require_tools gh git jq curl envsubst

repository=$(gh repo view --json nameWithOwner -q .nameWithOwner)
github_api_repo_url="https://api.github.com/repos/${repository}"

echo "Create draft release: repository: ${repository}, tag: ${release_tag}, output file: ${release_id_output_file}"

echo "Resolving component versions"
export ISTIO_VERSION ENVOY_VERSION
ISTIO_VERSION=$("${script_dir}/../get-module-istio-version.sh")
ENVOY_VERSION=$("${script_dir}/../get-module-envoy-version.sh" "${ISTIO_VERSION}")

echo "Computing changelog URL"
export CHANGELOG_URL
previous_tag=$("${script_dir}/get-previous-release-tag.sh" "${release_tag}")
echo "Previous tag: ${previous_tag}"
CHANGELOG_URL="https://github.com/${repository}/compare/${previous_tag}...${release_tag}"

echo "Assembling release notes from PR descriptions"
release_notes_file=$(mktemp)
"${script_dir}/assemble-release-notes.sh" "${release_notes_file}" "${previous_tag}" "${release_tag}"
export RELEASE_NOTES
RELEASE_NOTES=$(cat "${release_notes_file}")

echo "Rendering release body"
body_file=$(mktemp)
envsubst '$RELEASE_NOTES $ISTIO_VERSION $ENVOY_VERSION $CHANGELOG_URL' \
  < "${script_dir}/release-body.md.tmpl" > "${body_file}"
body=$(cat "${body_file}")

echo "Looking for existing draft release with tag ${release_tag}..."
existing_id=$(gh release list --repo "${repository}" --json tagName,isDraft,id \
  | jq -r ".[] | select(.tagName == \"${release_tag}\" and .isDraft == true) | .id" 2>/dev/null || true)

if [ -n "${existing_id}" ]; then
  echo "Found existing draft release (id: ${existing_id}), updating body..."
  curl -s -S -f -L \
    -X PATCH \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${github_api_repo_url}/releases/${existing_id}" \
    -d "$(jq -n --arg body "${body}" '{"body": $body}')" > /dev/null
  release_id="${existing_id}"
else
  echo "No existing draft release found, creating new draft for ${release_tag}..."
  json_payload=$(jq -n \
    --arg tag_name "${release_tag}" \
    --arg name "${release_tag}" \
    --arg body "${body}" \
    '{"tag_name": $tag_name, "name": $name, "body": $body, "draft": true}')
  release_id=$(curl -s -S -f -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${github_api_repo_url}/releases" \
    -d "${json_payload}" | jq -r '.id')
  echo "Created draft release (id: ${release_id})"
fi

echo "Storing release ID in file ${release_id_output_file}"
echo "${release_id}" > "${release_id_output_file}"
