#!/usr/bin/env bash
# sync-develop.sh, run against throwaway repositories shaped like Genesi's:
# develop with work of its own, main moved on, and the package folder changed
# on both sides (what made every hand merge conflict). No network.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sync-develop.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
check() {
    if [ "$2" = 0 ]; then echo "  PASS  $1"; else echo "  FAIL  $1${3:+  — $3}"; fails=$((fails + 1)); fi
}

make_repo() {   # make_repo <dir>: origin (bare) + a clone with main and develop
    local o="$1/origin.git" w="$1/work"
    git init -q --bare "$o"
    git clone -q "$o" "$w" 2>/dev/null
    cd "$w"
    git config user.email t@t; git config user.name t
    git checkout -q -b main
    mkdir -p genesi-arch/repo/x86_64 genesi-arch/packages/foo
    echo "pkgrel=1" > genesi-arch/packages/foo/PKGBUILD
    echo "foo-1" > genesi-arch/repo/x86_64/foo-1.pkg.tar.zst
    echo "db v1" > genesi-arch/repo/x86_64/genesi.db
    git add -A; git commit -q -m base
    git push -q origin main
    git checkout -q -b develop
    echo "kde work" > genesi-arch/packages/foo/kde.qml
    echo "db testing v1" > genesi-arch/repo/x86_64/genesi-testing.db
    echo "foo-1-testing" > genesi-arch/repo/x86_64/foo-1.pkg.tar.zst
    git add -A; git commit -q -m "develop work"
    git push -q origin develop
    git checkout -q main
    echo "pkgrel=2" > genesi-arch/packages/foo/PKGBUILD
    git rm -q genesi-arch/repo/x86_64/foo-1.pkg.tar.zst
    echo "foo-2" > genesi-arch/repo/x86_64/foo-2.pkg.tar.zst
    echo "db v2" > genesi-arch/repo/x86_64/genesi.db
    git add -A; git commit -q -m "stable fix"
    git push -q origin main
    git fetch -q origin
    git checkout -q develop
}

echo "== main moved on, develop has its own work =="
make_repo "$TMP/a"
bash "$SCRIPT" >/dev/null 2>&1
check "the merge succeeds" "$?"
check "develop now contains main" "$(git merge-base --is-ancestor origin/main HEAD; echo $?)"
check "develop's own work is kept" "$([ -f genesi-arch/packages/foo/kde.qml ]; echo $?)"
check "main's fix is in" "$(grep -q pkgrel=2 genesi-arch/packages/foo/PKGBUILD; echo $?)"
check "the package folder is main's" \
      "$([ -f genesi-arch/repo/x86_64/foo-2.pkg.tar.zst ] && [ ! -f genesi-arch/repo/x86_64/foo-1.pkg.tar.zst ] && grep -q 'db v2' genesi-arch/repo/x86_64/genesi.db; echo $?)"
check "...plus develop's testing index" "$(grep -q 'db testing v1' genesi-arch/repo/x86_64/genesi-testing.db; echo $?)"
check "nothing left uncommitted" "$([ -z "$(git status --porcelain)" ]; echo $?)"
check "nothing was pushed (SYNC_PUSH not set)" \
      "$([ "$(git rev-parse origin/develop)" != "$(git rev-parse HEAD)" ]; echo $?)"
out="$(bash "$SCRIPT" 2>&1)"
check "a second run has nothing to do" "$(echo "$out" | grep -q 'nothing to sync'; echo $?)"

echo "== a real conflict outside the package folder =="
make_repo "$TMP/b"
echo "develop says 3" > genesi-arch/packages/foo/PKGBUILD
git commit -q -am "develop edits the same line"
before="$(git rev-parse HEAD)"
bash "$SCRIPT" >/dev/null 2>&1
rc=$?
check "the run fails" "$([ "$rc" != 0 ]; echo $?)" "exit $rc"
check "develop is left exactly as it was" "$([ "$(git rev-parse HEAD)" = "$before" ] && [ -z "$(git status --porcelain)" ]; echo $?)"

echo "== pushing =="
make_repo "$TMP/c"
SYNC_PUSH=1 bash "$SCRIPT" >/dev/null 2>&1
check "SYNC_PUSH=1 pushes develop" "$([ "$(git rev-parse origin/develop)" = "$(git rev-parse HEAD)" ]; echo $?)"
check "...as a fast-forward of the old develop (no rewrite)" \
      "$(git merge-base --is-ancestor "$(git rev-parse HEAD~1)" origin/develop; echo $?)"

echo
[ "$fails" = 0 ] && { echo "sync develop: OK"; exit 0; }
echo "sync develop: $fails failure(s)"; exit 1
