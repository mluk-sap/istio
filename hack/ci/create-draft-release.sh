#!/usr/bin/env bash

# Creates a draft GitHub release and writes the release ID to a file.
# Release notes are assembled on-the-fly from merged PR descriptions.
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

REPOSITORY=$(gh repo view --json nameWithOwner -q .nameWithOwner)
github_api_repo_url="https://api.github.com/repos/${REPOSITORY}"

echo "Create draft release: repository: ${REPOSITORY}, tag: ${release_tag}, output file: ${release_id_output_file}"

echo "Resolving component versions"
export ISTIO_VERSION ENVOY_VERSION
ISTIO_VERSION=$("${script_dir}/../get-module-istio-version.sh")
ENVOY_VERSION=$("${script_dir}/../get-module-envoy-version.sh" "${ISTIO_VERSION}")

echo "Computing changelog URL"
export CHANGELOG_URL
previous_tag=$("${script_dir}/get-previous-release-tag.sh" "${release_tag}")
echo "Previous tag: ${previous_tag}"
CHANGELOG_URL="https://github.com/${REPOSITORY}/compare/${previous_tag}...${release_tag}"

echo "Assembling release notes from PR descriptions"
release_notes_file=$(mktemp)
"${script_dir}/assemble-release-notes.sh" "${previous_tag}" "${release_notes_file}"
export RELEASE_NOTES
RELEASE_NOTES=$(cat "${release_notes_file}")

echo "Rendering release body"
body=$(envsubst '$RELEASE_NOTES $ISTIO_VERSION $ENVOY_VERSION $CHANGELOG_URL' \
  < "${script_dir}/release-body.md.tmpl")

json_payload=$(jq -n \
  --arg tag_name "${release_tag}" \
  --arg name "${release_tag}" \
  --arg body "${body}" \
  '{
    "tag_name": $tag_name,
    "name": $name,
    "body": $body,
    "draft": true
  }')

echo "Creating release"
curl_response=$(curl -s -S -f -L \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${github_api_repo_url}/releases" \
  -d "${json_payload}")

echo "Storing release ID in file ${release_id_output_file}"
echo "${curl_response}" | jq -r ".id" > "${release_id_output_file}"
