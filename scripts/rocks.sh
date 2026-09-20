# Finds the development rock tree a worktree should be using. Sourced rather
# than run, because the answer is delivered by creating a link the caller then
# reads through its own `$ROOT/.rocks`.
#
# `.rocks` is ignored, so it belongs to a checkout rather than to a revision,
# and a worktree starts without one. `scripts/worktree` links the originating
# checkout's tree, but a worktree made any other way -- `git worktree add` run
# by hand, or by a tool that has never heard of this repository -- does not get
# that, and the twenty-eight suites needing a rock tree then fail as missing
# modules. Nothing in the failure says the worktree skipped a setup step, so
# the time goes on the wrong question.
#
# Linking it here means how a worktree was made stops deciding whether its
# tests can run.

# Links ROOT/.rocks at the tree the main worktree already has, if ROOT has none
# and is a linked worktree of a checkout that does. Silent and best-effort: it
# reports nothing and returns success either way, because every caller's next
# move is the same whether or not a tree was found.
link_development_rocks() {
    rocks_root=$1

    # A path already there is the answer, whatever it points at. `-L` catches a
    # dangling link too: a broken one is a state somebody made deliberately or
    # broke by moving a checkout, and replacing it silently would lose that.
    if [ -e "$rocks_root/.rocks" ] || [ -L "$rocks_root/.rocks" ]; then
        return 0
    fi

    # The common directory is the main worktree's `.git`, so its parent is the
    # checkout that owns `.rocks`. In the main worktree itself this is `.git`,
    # whose parent is the root we started from -- the equality below then stops
    # us, which is right: a main checkout with no rock tree has not been
    # provisioned, and the build that provisions it is the answer there.
    rocks_common=$(cd "$rocks_root" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 0
    [ -n "$rocks_common" ] || return 0
    rocks_origin=$(cd "$rocks_root" 2>/dev/null && cd "$(dirname "$rocks_common")" 2>/dev/null && pwd) || return 0
    [ -n "$rocks_origin" ] || return 0
    [ "$rocks_origin" != "$rocks_root" ] || return 0
    [ -d "$rocks_origin/.rocks" ] || return 0

    # A link rather than a copy, matching `scripts/worktree`: a build that
    # installs a rock writes through it, so every worktree reaches one tree and
    # the rock installed from any of them is there for all of them.
    #
    # Failure is not a problem to report. Windows refuses a symlink without the
    # privilege, and two commands starting at once race to make the same one;
    # both leave a tree no worse than the one we found, and the caller goes on
    # to fail the way it would have anyway.
    ln -s "$rocks_origin/.rocks" "$rocks_root/.rocks" 2>/dev/null || true
    return 0
}
