#!/bin/sh
# A build superseded on main must not publish after a newer build.
set -eu
current=$(gh api "repos/$GITHUB_REPOSITORY/git/ref/heads/main" --jq .object.sha)
if [ "$current" = "$GITHUB_SHA" ]; then
    printf 'deploy=true\n' >> "$GITHUB_OUTPUT"
else
    printf 'deploy=false\n' >> "$GITHUB_OUTPUT"
    echo 'A newer main revision exists; skip this deployment.'
fi
