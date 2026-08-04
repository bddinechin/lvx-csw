#!/usr/bin/env bash
# Synchronize this clone of lvx-csw with work pushed from another machine.
#
# Run from anywhere:  ./sync-from-work.sh
#
# Beyond a plain "git pull && git submodule update", this handles the three
# things that silently go wrong in a submodule superproject:
#
#  1. `git submodule update` checks out the recorded commit as a DETACHED
#     HEAD, so a clone drifts off its branches the first time it updates.
#     .gitmodules now carries `update = merge` for every submodule, which
#     keeps the branch -- but that field only reaches a clone's .git/config
#     via `git submodule init`, so this script runs it.
#
#  2. `git submodule init` does NOT overwrite a value already set locally.
#     A clone that has `submodule.<name>.update = checkout` from earlier
#     keeps detaching with no warning. This script clears such values.
#
#  3. `update = merge` keeps a branch you are ON; it cannot put you back on
#     one. Submodules already detached stay detached. This script re-attaches
#     them to the branch .gitmodules names -- but only when that is provably
#     lossless (see the containment check below).
#
# Nothing here rebases, resets, forces or discards. Anything it will not do
# safely, it reports and leaves alone.
set -uo pipefail

cd "$(dirname "$0")" || exit 1
ROOT=$(pwd)

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '   \033[33m!! %s\033[0m\n' "$*"; }

paths() { git config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}'; }
name_of() {  # path -> submodule name (they can differ)
  git config -f .gitmodules --get-regexp '^submodule\..*\.path$' \
    | awk -v p="$1" '$2 == p { sub(/^submodule\./, "", $1); sub(/\.path$/, "", $1); print $1 }'
}

# ---------------------------------------------------------------- 0. preflight
say "Checking for local work that a sync could disturb"
DIRTY=0
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    warn "superproject has uncommitted tracked changes:"
    git status --short --untracked-files=no | sed 's/^/      /'
    DIRTY=1
fi
for p in $(paths); do
    [ -d "$ROOT/$p/.git" ] || [ -f "$ROOT/$p/.git" ] || continue
    if [ -n "$(git -C "$ROOT/$p" status --porcelain --untracked-files=no)" ]; then
        warn "$p has uncommitted changes -- it will be left alone below"
        DIRTY=1
    fi
done
[ "$DIRTY" -eq 0 ] && info "clean"

# ------------------------------------------------------- 1. superproject pull
say "Pulling the superproject"
if ! git pull --ff-only; then
    warn "fast-forward pull failed -- you have local commits or diverged."
    warn "Resolve by hand (git pull --rebase, or merge), then re-run. Stopping."
    exit 1
fi

# ------------------------------------- 2. clear stale local 'update' settings
say "Clearing stale submodule.*.update values"
CLEARED=0
while read -r key val; do
    [ -z "${key:-}" ] && continue
    if [ "$val" != "merge" ]; then
        info "unsetting $key (was '$val')"
        git config --unset "$key"
        CLEARED=1
    fi
done < <(git config --local --get-regexp '^submodule\..*\.update$' 2>/dev/null)
[ "$CLEARED" -eq 0 ] && info "none stale"

# -------------------------------------------- 3. init: copy .gitmodules -> config
say "Running submodule init (copies url/branch/update into .git/config)"
git submodule sync --recursive >/dev/null
git submodule init
for p in $(paths); do
    n=$(name_of "$p")
    u=$(git config --get "submodule.$n.update" || true)
    [ "$u" = "merge" ] || warn "$p: update='$u' (expected 'merge')"
done

# ------------------------------------------------ 4. re-attach detached HEADs
say "Re-attaching detached submodules to their declared branches"
ATTACHED=0
for p in $(paths); do
    d="$ROOT/$p"
    [ -e "$d/.git" ] || { info "$p: not initialized yet (will be cloned below)"; continue; }
    cur=$(git -C "$d" branch --show-current)
    [ -n "$cur" ] && continue                      # already on a branch

    n=$(name_of "$p")
    br=$(git config -f .gitmodules --get "submodule.$n.branch" || true)
    [ -n "$br" ] || { warn "$p: detached and .gitmodules names no branch -- skipped"; continue; }

    if [ -n "$(git -C "$d" status --porcelain --untracked-files=no)" ]; then
        warn "$p: detached but has uncommitted changes -- not touching it"
        continue
    fi

    git -C "$d" fetch -q origin "$br" 2>/dev/null
    head=$(git -C "$d" rev-parse HEAD)
    # Only attach when the branch already CONTAINS the detached commit.
    # Otherwise the detached HEAD holds work the branch does not, and
    # checking out the branch would strand it.
    if git -C "$d" merge-base --is-ancestor "$head" "origin/$br" 2>/dev/null; then
        git -C "$d" checkout -q "$br" 2>/dev/null || git -C "$d" checkout -q -b "$br" "origin/$br"
        info "$p -> $br"
        ATTACHED=1
    else
        warn "$p: HEAD $(git -C "$d" rev-parse --short HEAD) is NOT contained in origin/$br."
        warn "     It may hold commits that branch lacks. Left detached -- inspect with:"
        warn "     git -C $p log --oneline origin/$br..HEAD"
    fi
done
[ "$ATTACHED" -eq 0 ] && info "nothing to re-attach"

# ------------------------------------------------------- 5. update submodules
say "Updating submodules to the commits the superproject records"
git submodule update --init --recursive

# ------------------------------------------------------------- 6. final report
say "Result"
printf '   %-26s %-14s %s\n' REPO BRANCH HEAD
printf '   %-26s %-14s %s\n' ---- ------ ----
printf '   %-26s %-14s %s\n' "lvx-csw (super)" \
       "$(git branch --show-current)" "$(git log --oneline -1 | cut -c1-40)"
for p in $(paths); do
    d="$ROOT/$p"
    [ -e "$d/.git" ] || { printf '   %-26s %s\n' "$p" "(not initialized)"; continue; }
    b=$(git -C "$d" branch --show-current)
    printf '   %-26s %-14s %s\n' "$p" "${b:-*DETACHED*}" \
           "$(git -C "$d" log --oneline -1 | cut -c1-40)"
done

echo
info "Any submodule marked '+' by 'git submodule status' has a checkout that"
info "differs from the recorded commit -- expected while you have local work,"
info "worth a look otherwise."
echo
