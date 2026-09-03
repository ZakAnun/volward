#!/usr/bin/env bash
# Link repo hooks into .git/hooks (no git config changes).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_src="$root/scripts/githooks/pre-commit"
chmod +x "$hook_src" "$root/scripts/check_dart_format.sh"

git_common="$(git -C "$root" rev-parse --git-common-dir)"
if [[ "$git_common" != /* ]]; then
  git_common="$(cd "$root/$git_common" && pwd)"
fi

dest="$git_common/hooks/pre-commit"
# Copy, don't symlink: worktree paths vanish after cleanup, and
# .git/hooks is shared across worktrees.
rm -f "$dest"
cp "$hook_src" "$dest"
chmod +x "$dest"
printf 'installed %s\n' "$dest"
