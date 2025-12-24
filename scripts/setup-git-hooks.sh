#!/bin/bash
#
# Setup Git Hooks Script
# Installs git hooks from scripts/hooks/ to .git/hooks/
#
# Usage:
#   ./scripts/setup-git-hooks.sh
#
# This script copies hooks from the version-controlled scripts/hooks/ directory
# to .git/hooks/ so they are active for git operations.

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOKS_SOURCE_DIR="${REPO_ROOT}/scripts/hooks"
HOOKS_TARGET_DIR="${REPO_ROOT}/.git/hooks"

# Check if hooks source directory exists
if [[ ! -d "$HOOKS_SOURCE_DIR" ]]; then
	echo "Error: Hooks source directory not found: $HOOKS_SOURCE_DIR" >&2
	exit 1
fi

# Check if git hooks directory exists
if [[ ! -d "$HOOKS_TARGET_DIR" ]]; then
	echo "Error: Git hooks directory not found: $HOOKS_TARGET_DIR" >&2
	echo "Are you in a git repository?" >&2
	exit 1
fi

echo "Setting up git hooks..."
echo "  Source: $HOOKS_SOURCE_DIR"
echo "  Target: $HOOKS_TARGET_DIR"
echo ""

# Install each hook from scripts/hooks/
HOOKS_INSTALLED=0
for hook_file in "${HOOKS_SOURCE_DIR}"/*; do
	# Skip if not a file
	[[ ! -f "$hook_file" ]] && continue

	# Get hook name (filename without path)
	hook_name=$(basename "$hook_file")
	target_hook="${HOOKS_TARGET_DIR}/${hook_name}"

	# Copy hook file
	cp "$hook_file" "$target_hook"
	chmod +x "$target_hook"

	echo "  ✓ Installed: $hook_name"
	((HOOKS_INSTALLED++)) || true
done

if [[ $HOOKS_INSTALLED -eq 0 ]]; then
	echo "  Warning: No hooks found in $HOOKS_SOURCE_DIR" >&2
	exit 1
fi

echo ""
echo "Successfully installed $HOOKS_INSTALLED git hook(s)."
echo ""
echo "Hooks will now run automatically on git operations."
