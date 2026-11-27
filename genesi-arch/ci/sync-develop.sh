#!/usr/bin/env bash
# Merge main into develop so the testing channel never holds stable back.
#
# [genesi-testing] sits ABOVE [genesi] in pacman.conf (it has to: pacman takes
# a package from the first repo that lists it, whatever the version). So any
# package the testing repo carries at an OLDER version than stable wins, and a
# tester stops getting stable's fixes until develop catches up. That happened
# for real: a tester kept the caelestia build broken by Arch's sndio 1.11
# update until develop was merged by hand. This runs after every stable
# publish and keeps develop >= main.
#
# - develop's own commits are kept: a normal merge, never a reset.
# - genesi-arch/repo/x86_64 (the published binaries) cannot merge: it is
#   rebuilt from the sources by the next testing publish anyway. It is taken
#   from main, plus develop's own genesi-testing.* index files.
# - any conflict OUTSIDE that folder stops the run without pushing: that is a
#   real disagreement between the branches and needs a person.
#
# Usage, from a full clone with origin/main and develop checked out:
#   bash genesi-arch/ci/sync-develop.sh            # merge and commit
#   SYNC_PUSH=1 bash genesi-arch/ci/sync-develop.sh  # ...and push develop
set -euo pipefail

REPO_DIR="genesi-arch/repo/x86_64"
MAIN_REF="${SYNC_MAIN_REF:-origin/main}"

if [ "$(git rev-parse --abbrev-ref HEAD)" != "develop" ]; then
    echo "::error::run this on the develop branch" >&2
    exit 2
fi

if git merge-base --is-ancestor "$MAIN_REF" HEAD; then
    echo "develop already contains $MAIN_REF; nothing to sync."
    echo "synced=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    exit 0
fi

git merge --no-commit --no-ff "$MAIN_REF" >/dev/null 2>&1 || true

conflicts="$(git diff --name-only --diff-filter=U | grep -v "^${REPO_DIR}/" || true)"
if [ -n "$conflicts" ]; then
    git merge --abort || true
    echo "::error::develop and main conflict outside the package folder; merge by hand:" >&2
    echo "$conflicts" >&2
    exit 1
fi

# The package folder: main's files, develop's testing indexes.
testing_entries="$(git ls-tree -r HEAD -- "$REPO_DIR" | grep "/genesi-testing\." || true)"
git rm -r -q --cached "$REPO_DIR" >/dev/null 2>&1 || true
{
    git ls-tree -r "$MAIN_REF" -- "$REPO_DIR" | grep -v "/genesi-testing\." || true
    printf '%s\n' "$testing_entries" | sed '/^$/d'
} | git update-index --index-info
git checkout -- "$REPO_DIR" 2>/dev/null || true
git clean -fdq -- "$REPO_DIR" 2>/dev/null || true

if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
    git merge --abort || true
    echo "::error::unresolved files left after the merge" >&2
    exit 1
fi

git commit -q -m "ci(testing): merge main into develop ($(git rev-parse --short "$MAIN_REF"))

Keeps the testing channel at or ahead of stable: [genesi-testing] is listed
first, so an older testing build would hold a stable fix back."
echo "merged $(git rev-parse --short "$MAIN_REF") into develop as $(git rev-parse --short HEAD)"
echo "synced=true" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "${SYNC_PUSH:-0}" = 1 ]; then
    git push origin HEAD:develop
fi
