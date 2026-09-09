#!/bin/bash
# sync-gh-pages.sh - publish bootstrap.sh to the branch that actually serves it.
#
# settings.jiun.dev is GitHub Pages from `gh-pages`, not the Worker in worker/ (see
# the README). That branch carries its own copy of bootstrap.sh, plus index.html as a
# byte-identical duplicate so `curl -LsSf https://settings.jiun.dev | bash` works with
# no path. Nothing syncs them automatically, and the copy once went stale for over
# five months - long enough that the live installer was missing the guard that refuses
# to `git reset --hard` over uncommitted local changes.
#
# Run this after committing any change to bootstrap.sh.
#
#   scripts/sync-gh-pages.sh              # show what would change
#   scripts/sync-gh-pages.sh --push       # commit and push to gh-pages

set -euo pipefail

PUSH=false
[[ "${1:-}" == "--push" ]] && PUSH=true

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

# Source the COMMITTED blob, not the working copy. Two reasons: gh-pages should only
# ever mirror a committed state, and on a machine with core.autocrlf=true the working
# copy has CRLF line endings - publishing those would ship a bootstrap.sh whose
# shebang is `#!/bin/bash\r`, which bash will not run.
SRC=$(mktemp); trap 'rm -f "$SRC"' EXIT
git show HEAD:bootstrap.sh > "$SRC" 2>/dev/null || {
    echo "bootstrap.sh not found at HEAD - commit it first" >&2; exit 1; }

if grep -q $'\r' "$SRC"; then
    echo "HEAD:bootstrap.sh contains CR bytes; refusing to publish" >&2
    exit 1
fi

# Never publish a script that does not parse.
bash -n "$SRC" || { echo "bootstrap.sh has syntax errors; refusing to publish" >&2; exit 1; }

git fetch origin gh-pages --quiet

if git show origin/gh-pages:bootstrap.sh > /tmp/.ghp-live 2>/dev/null && \
   cmp -s /tmp/.ghp-live "$SRC"; then
    rm -f /tmp/.ghp-live
    echo "gh-pages is already up to date with HEAD:bootstrap.sh"
    exit 0
fi

echo "gh-pages bootstrap.sh differs from HEAD:bootstrap.sh:"
diff /tmp/.ghp-live "$SRC" || true
rm -f /tmp/.ghp-live
echo

if [[ "$PUSH" != "true" ]]; then
    echo "Re-run with --push to publish."
    exit 0
fi

# Work in a detached worktree so the current branch and index are untouched.
WT=$(mktemp -d)
cleanup() { git worktree remove --force "$WT" 2>/dev/null || true; rm -rf "$WT" "$SRC"; }
trap cleanup EXIT
git worktree add --quiet --detach "$WT" origin/gh-pages
SHA=$(git rev-parse --short HEAD)
cd "$WT"

# index.html is a duplicate of the script on purpose: Pages serves it for a pathless
# request, which is what the documented one-liner relies on.
cp "$SRC" bootstrap.sh
cp "$SRC" index.html

if git diff --quiet; then
    echo "nothing to commit"
    exit 0
fi

git add bootstrap.sh index.html
git commit --quiet -m "chore(pages): sync bootstrap.sh from $SHA"
git push --quiet origin HEAD:gh-pages
echo "pushed to gh-pages: $(git rev-parse --short HEAD)"
