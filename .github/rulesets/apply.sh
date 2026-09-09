#!/usr/bin/env bash
# Apply `.github/rulesets/main.json` to the repository.
#
# The trunk had no protection at all: a defect could land, every subsequent
# unrelated change would report it again, and the run that would have caught it
# was cancelled by the next push. A ruleset is the only thing that makes
# `required-ci` mean "this exact revision passed" rather than "some revision
# near this one passed once".
#
# Two properties are the point, and both are in the JSON rather than here:
#
#   * `merge_queue` with `grouping_strategy: ALLGREEN` -- the queue builds the
#     revision that will actually advance `main`, so a result is never inherited
#     from a different parent; and
#   * `strict_required_status_checks_policy` -- a pull request must be current
#     with its base before it can merge.
#
# This changes shared repository settings, so it is a deliberate act with a
# person behind it rather than something a workflow does. Run it once:
#
#     .github/rulesets/apply.sh [OWNER/REPO]
#
# It creates the ruleset, or updates the existing one of the same name. Pass
# `--dry-run` to see what would be sent.
set -euo pipefail

repository=${1:-}
if [ "$repository" = "--dry-run" ]; then
    repository=""
fi
if [ -z "$repository" ]; then
    repository=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi
definition=$(dirname "$0")/main.json

for argument in "$@"; do
    if [ "$argument" = "--dry-run" ]; then
        echo "would apply to $repository:"
        cat "$definition"
        exit 0
    fi
done

existing=$(gh api "repos/${repository}/rulesets" --jq \
    '.[] | select(.name == "main") | .id' 2>/dev/null || true)

if [ -n "$existing" ]; then
    echo "updating ruleset $existing on $repository"
    gh api --method PUT "repos/${repository}/rulesets/${existing}" \
        --input "$definition"
else
    echo "creating the ruleset on $repository"
    gh api --method POST "repos/${repository}/rulesets" --input "$definition"
fi

echo
echo "required-ci is now the gate. Verify with:"
echo "  gh api repos/${repository}/rulesets --jq '.[] | {id, name, enforcement}'"
