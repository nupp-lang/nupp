#!/usr/bin/env bash
# Apply `.github/rulesets/main.json` to the repository.
#
# The trunk had no protection at all: a defect could land, every subsequent
# unrelated change would report it again, and the run that would have caught it
# was cancelled by the next push. A ruleset is the only thing that makes
# `required-ci` mean "this exact revision passed" rather than "some revision
# near this one passed once".
#
# It requires one thing: `required-ci` must already be passing for the exact
# commit being pushed. It deliberately requires **no pull request and no merge
# queue**. This repository is one person working out of worktrees, and
# `AGENTS.md` describes the flow as rebasing `main` into a worktree and
# fast-forwarding it back. A pull request rule would forbid that flow outright
# while adding nothing: the guarantee wanted here is that the revision reaching
# the trunk is a revision that passed, not that somebody reviewed it.
#
# So the loop stays what it was, with one wait added:
#
#     git push origin my-worktree-branch    # CI runs on this exact commit
#     # ... required-ci goes green ...
#     git push origin my-worktree-branch:main
#
# The second push is the same SHA, which already has a passing `required-ci`,
# so the ruleset admits it. A commit nothing has tested is refused, which is the
# whole point and the only behaviour change.
#
# `strict_required_status_checks_policy` keeps the trunk fast-forward-only in
# practice: what is pushed must be current with `main`. `non_fast_forward` and
# `deletion` stop history being rewritten or the branch removed.
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
