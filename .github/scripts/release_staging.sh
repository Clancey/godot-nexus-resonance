#!/usr/bin/env bash
# Run-owned draft Releases are the only cross-job binary transport.
set -euo pipefail

: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}"
[[ "$GITHUB_RUN_ID" =~ ^[0-9]+$ && "$GITHUB_RUN_ATTEMPT" =~ ^[0-9]+$ ]]
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]]
TAG="ci-staging-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
TITLE="CI staging ${GITHUB_RUN_ID}/${GITHUB_RUN_ATTEMPT}"
OWNER="CI staging only: ${GITHUB_REPOSITORY} run ${GITHUB_RUN_ID} attempt ${GITHUB_RUN_ATTEMPT} commit ${GITHUB_SHA}"
export STAGING_TAG="$TAG" STAGING_TITLE="$TITLE" STAGING_OWNER="$OWNER"

require_absent_tag() {
  local response
  response="$(mktemp)"
  if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" >"$response"; then
    rm -f "$response"
    echo "Refusing access: staging tag already exists: $TAG" >&2
    exit 1
  fi
  python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert str(r.get("status")) == "404", r' "$response"
  rm -f "$response"
}

validate() {
  [[ "${STAGING_RELEASE_ID:?}" =~ ^[0-9]+$ ]]
  gh api "repos/$GITHUB_REPOSITORY/releases/$STAGING_RELEASE_ID" | python3 -c '
import json, os, sys
r = json.load(sys.stdin)
expected = {
    "id": int(os.environ["STAGING_RELEASE_ID"]),
    "draft": True,
    "tag_name": os.environ["STAGING_TAG"],
    "name": os.environ["STAGING_TITLE"],
    "body": os.environ["STAGING_OWNER"],
    "target_commitish": os.environ["GITHUB_SHA"],
}
if any(r.get(k) != v for k, v in expected.items()) or r.get("author", {}).get("login") != "github-actions[bot]":
    sys.exit("Refusing access: staging draft is not owned by this run/attempt/commit")
'
  # REST lookup by tag excludes drafts. The CLI resolves drafts through GraphQL.
  # Check its ID too because gh release upload/download address a tag, not an ID.
  resolved_id="$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json databaseId --jq .databaseId)"
  if [[ "$resolved_id" != "$STAGING_RELEASE_ID" ]]; then
    echo "Refusing access: staging tag resolves to a different release ID" >&2
    exit 1
  fi
  require_absent_tag
}

case "${1:-}" in
  create)
    # A draft must never reuse an existing tag or release (including prior attempts).
    # Non-404 API failures must fail closed, not masquerade as an absent resource.
    require_absent_tag
    existing="$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases" --jq ".[] | select(.tag_name == \"$TAG\") | .id")"
    if [[ -n "$existing" ]]; then
      echo "Refusing to reuse existing staging release: $TAG" >&2
      exit 1
    fi
    STAGING_RELEASE_ID="$(gh api --method POST "repos/$GITHUB_REPOSITORY/releases" \
      -f tag_name="$TAG" -f target_commitish="$GITHUB_SHA" -f name="$TITLE" \
      -f body="$OWNER" -F draft=true -F prerelease=false --jq .id)"
    export STAGING_RELEASE_ID
    echo "release_id=$STAGING_RELEASE_ID" >> "${GITHUB_OUTPUT:?}"
    validate
    echo "Draft staging: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/$STAGING_RELEASE_ID" >> "${GITHUB_STEP_SUMMARY:?}"
    ;;
  upload)
    shift
    (( $# > 0 ))
    validate
    # Deliberately no --clobber: duplicate names must fail, never overwrite.
    gh release upload "$TAG" "$@" --repo "$GITHUB_REPOSITORY"
    ;;
  download)
    [[ $# == 3 ]]
    validate
    gh release download "$TAG" --pattern "$2" --dir "$3" --repo "$GITHUB_REPOSITORY"
    ;;
  delete)
    validate
    gh api --method DELETE "repos/$GITHUB_REPOSITORY/releases/$STAGING_RELEASE_ID"
    echo "Deleted owned staging draft $STAGING_RELEASE_ID ($TAG); no tags modified."
    ;;
  *)
    echo "Usage: $0 create | upload FILE... | download PATTERN DIRECTORY | delete" >&2
    exit 2
    ;;
esac
