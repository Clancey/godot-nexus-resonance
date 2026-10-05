#!/usr/bin/env bash
# Only the draft owned by this exact run/attempt/commit may be changed.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]]
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]
tag="ci-stage-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
marker="CI staging: ${GITHUB_REPOSITORY} run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT} commit ${GITHUB_SHA}"
endpoint="repos/${GITHUB_REPOSITORY}"

fail() { echo "::error::$*" >&2; exit 1; }

validate() {
  [[ "${STAGING_RELEASE_ID:-}" =~ ^[0-9]+$ ]] || fail "Missing numeric staging release ID"
  gh api "$endpoint/releases/$STAGING_RELEASE_ID" |
    jq -e --arg tag "$tag" --arg marker "$marker" --arg sha "$GITHUB_SHA" \
      --argjson id "$STAGING_RELEASE_ID" \
      '.id == $id and .draft == true and .tag_name == $tag and
       .name == $tag and .body == $marker and .target_commitish == $sha' >/dev/null ||
    fail "Staging draft identity mismatch"
  # A draft with an unpublished tag needs no git ref; never delete or move a tag.
  gh api "$endpoint/git/matching-refs/tags/$tag" |
    jq -e --arg ref "refs/tags/$tag" 'all(.[]; .ref != $ref)' >/dev/null ||
    fail "Staging tag unexpectedly exists"
}

case "${1:-}" in
  create)
    gh api --paginate "$endpoint/releases?per_page=100" |
      jq -se --arg tag "$tag" 'all(.[][]; .tag_name != $tag)' >/dev/null ||
      fail "Staging release name already exists"
    gh api "$endpoint/git/matching-refs/tags/$tag" |
      jq -e --arg ref "refs/tags/$tag" 'all(.[]; .ref != $ref)' >/dev/null ||
      fail "Staging tag already exists"
    STAGING_RELEASE_ID="$(gh api --method POST "$endpoint/releases" \
      -f tag_name="$tag" -f target_commitish="$GITHUB_SHA" \
      -f name="$tag" -f body="$marker" -F draft=true --jq .id)"
    export STAGING_RELEASE_ID
    validate
    echo "release_id=$STAGING_RELEASE_ID" >> "${GITHUB_OUTPUT:?}"
    {
      echo "### Temporary build staging"
      echo "Draft: \`$tag\`; release ID: \`$STAGING_RELEASE_ID\`."
      echo "Run: $GITHUB_RUN_ID / attempt $GITHUB_RUN_ATTEMPT; commit: \`$GITHUB_SHA\`."
      echo "No tag is created. Draft-only runs retain bundles for inspection and explicit cleanup."
    } >> "${GITHUB_STEP_SUMMARY:?}"
    ;;
  upload)
    shift
    (($# > 0)) || fail "No files to upload"
    validate
    # gh refuses duplicate filenames by default. Never use its overwrite flag.
    gh release upload "$tag" "$@" --repo "$GITHUB_REPOSITORY"
    ;;
  download)
    shift
    (($# == 2)) || fail "Expected asset name and destination"
    validate
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "$1" --dir "$2"
    ;;
  delete)
    validate
    gh api --method DELETE "$endpoint/releases/$STAGING_RELEASE_ID"
    echo "Deleted only verified draft $tag (ID $STAGING_RELEASE_ID); no git refs touched."
    ;;
  inspect)
    validate
    gh api "$endpoint/releases/$STAGING_RELEASE_ID" \
      --jq '{id, tag_name, draft, target_commitish, body, assets: [.assets[] | {name, size, digest}]}'
    ;;
  *) fail "Usage: $0 create|upload FILE...|download NAME DIR|inspect|delete" ;;
esac
