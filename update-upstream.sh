#!/usr/bin/env bash
#
# Merges a NodeBB upstream release tag into a deploy branch of this fork.
#
# Usage:
#   ./update-upstream.sh            # targets the "dev" branch
#   ./update-upstream.sh <branch>   # targets another branch
#
# The script never pushes. It prints the push command at the end.

set -euo pipefail

UPSTREAM_REMOTE="upstream"
UPSTREAM_URL="https://github.com/NodeBB/NodeBB.git"
ORIGIN_REMOTE="origin"
TARGET_BRANCH="${1:-dev}"
# Stable releases only: vMAJOR.MINOR.PATCH (excludes -beta, -rc, etc.)
STABLE_TAG_REGEX='^v[0-9]+\.[0-9]+\.[0-9]+$'
MAX_TAGS_SHOWN=10

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWarning:\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
	local answer
	read -rp "$1 [y/N] " answer
	[[ "$answer" =~ ^[Yy]$ ]]
}

# --- Preconditions -----------------------------------------------------------

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
	|| fail "Not inside a git repository. Run this from your fork's clone."

cd "$(git rev-parse --show-toplevel)"

if [ -e "$(git rev-parse --git-path MERGE_HEAD)" ]; then
	fail "A merge is already in progress. Finish it or run 'git merge --abort' first."
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
	fail "You have uncommitted changes. Commit or stash them first."
fi

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
	warn "No '$UPSTREAM_REMOTE' remote found."
	if confirm "Add '$UPSTREAM_REMOTE' -> $UPSTREAM_URL ?"; then
		git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
	else
		fail "Upstream remote is required."
	fi
fi

# --- Fetch -------------------------------------------------------------------

info "Fetching $ORIGIN_REMOTE..."
git fetch "$ORIGIN_REMOTE"

info "Fetching tags from $UPSTREAM_REMOTE..."
git fetch "$UPSTREAM_REMOTE" --tags

# --- Prepare target branch ---------------------------------------------------

if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
	git checkout --quiet "$TARGET_BRANCH"
elif git show-ref --verify --quiet "refs/remotes/$ORIGIN_REMOTE/$TARGET_BRANCH"; then
	info "Creating local '$TARGET_BRANCH' tracking $ORIGIN_REMOTE/$TARGET_BRANCH"
	git checkout --quiet -b "$TARGET_BRANCH" --track "$ORIGIN_REMOTE/$TARGET_BRANCH"
else
	fail "Branch '$TARGET_BRANCH' exists neither locally nor on $ORIGIN_REMOTE."
fi

# Make sure the local branch matches what is deployed on origin.
if git show-ref --verify --quiet "refs/remotes/$ORIGIN_REMOTE/$TARGET_BRANCH"; then
	LOCAL_SHA="$(git rev-parse "$TARGET_BRANCH")"
	REMOTE_SHA="$(git rev-parse "$ORIGIN_REMOTE/$TARGET_BRANCH")"
	if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
		if git merge-base --is-ancestor "$LOCAL_SHA" "$REMOTE_SHA"; then
			info "Fast-forwarding local '$TARGET_BRANCH' to $ORIGIN_REMOTE/$TARGET_BRANCH"
			git merge --quiet --ff-only "$ORIGIN_REMOTE/$TARGET_BRANCH"
		elif git merge-base --is-ancestor "$REMOTE_SHA" "$LOCAL_SHA"; then
			warn "Local '$TARGET_BRANCH' has commits not yet pushed to $ORIGIN_REMOTE."
			confirm "Continue anyway?" || exit 1
		else
			fail "Local '$TARGET_BRANCH' and $ORIGIN_REMOTE/$TARGET_BRANCH have diverged. Reconcile them first."
		fi
	fi
fi

# --- Determine current and available releases --------------------------------

CURRENT_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$TARGET_BRANCH" 2>/dev/null || true)"
[ -n "$CURRENT_TAG" ] || fail "Could not determine which NodeBB release '$TARGET_BRANCH' is based on."

info "'$TARGET_BRANCH' is currently based on NodeBB $CURRENT_TAG"

# Stable tags newer than the current base (not already merged), newest first.
CANDIDATES=()
while IFS= read -r tag; do
	[[ "$tag" =~ $STABLE_TAG_REGEX ]] || continue
	if ! git merge-base --is-ancestor "$tag" "$TARGET_BRANCH"; then
		CANDIDATES+=("$tag")
	fi
	[ "${#CANDIDATES[@]}" -ge "$MAX_TAGS_SHOWN" ] && break
done < <(git tag -l 'v[0-9]*' --sort=-v:refname)

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
	info "Already up to date: no stable release newer than $CURRENT_TAG."
	exit 0
fi

echo
echo "Available releases newer than $CURRENT_TAG:"
for i in "${!CANDIDATES[@]}"; do
	label=""
	[ "$i" -eq 0 ] && label="  (latest)"
	printf '  %2d) %s%s\n' "$((i + 1))" "${CANDIDATES[$i]}" "$label"
done
echo

read -rp "Select a release to merge [1]: " choice
choice="${choice:-1}"
[[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#CANDIDATES[@]}" ] \
	|| fail "Invalid selection: $choice"

TAG="${CANDIDATES[$((choice - 1))]}"

# --- Pre-merge summary -------------------------------------------------------

UPSTREAM_COMMITS="$(git rev-list --count "$TARGET_BRANCH..$TAG")"

# Files you changed relative to your base release vs files upstream changed
# between your base release and the selected one.
OUR_FILES="$(git diff --name-only "$CURRENT_TAG" "$TARGET_BRANCH" | sort)"
THEIR_FILES="$(git diff --name-only "$CURRENT_TAG" "$TAG" | sort)"
OVERLAP="$(comm -12 <(printf '%s\n' "$OUR_FILES") <(printf '%s\n' "$THEIR_FILES") | sed '/^$/d')"

echo
info "Merge plan"
echo "  Branch:          $TARGET_BRANCH"
echo "  From release:    $CURRENT_TAG"
echo "  To release:      $TAG"
echo "  Upstream commits: $UPSTREAM_COMMITS"
echo
if [ -n "$OVERLAP" ]; then
	warn "Upstream also changed files you have patched. Review these after the merge:"
	printf '%s\n' "$OVERLAP" | sed 's/^/    /'
else
	echo "  No overlap between your patched files and upstream changes."
fi
echo

confirm "Merge $TAG into '$TARGET_BRANCH'?" || { info "Aborted, nothing changed."; exit 0; }

# --- Merge -------------------------------------------------------------------

if ! git merge --no-ff -m "Merge NodeBB $TAG into $TARGET_BRANCH" "$TAG"; then
	echo
	warn "Merge stopped on conflicts in:"
	git diff --name-only --diff-filter=U | sed 's/^/    /'
	echo
	echo "To finish:"
	echo "  1. Resolve the conflicts in the files above"
	echo "  2. git add <files>"
	echo "  3. git commit"
	echo "  4. git push $ORIGIN_REMOTE $TARGET_BRANCH"
	echo
	echo "To cancel instead:  git merge --abort"
	exit 1
fi

# --- Done --------------------------------------------------------------------

PKG_VERSION="$(git show HEAD:package.json | grep -m1 '"version"' | sed -E 's/.*"version": *"([^"]+)".*/\1/')"

echo
info "Merged $TAG into '$TARGET_BRANCH' (package.json version: $PKG_VERSION)"
if [ -n "$OVERLAP" ]; then
	warn "The merge applied cleanly, but double-check the overlapping files listed above."
fi
echo
echo "Review with:   git log --oneline -n 5 $TARGET_BRANCH"
echo "Push with:     git push $ORIGIN_REMOTE $TARGET_BRANCH"
