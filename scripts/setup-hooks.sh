#!/usr/bin/env bash
# Setup script to install Git hooks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR=".githooks"
GIT_HOOKS_DIR=".git/hooks"

echo "Installing Git hooks..."

if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "Error: .git/hooks directory not found. Make sure you're in the repository root."
    exit 1
fi

# Copy hooks from .githooks to .git/hooks
for hook in pre-commit commit-msg; do
    if [ -f "$HOOKS_DIR/$hook" ]; then
        cp "$HOOKS_DIR/$hook" "$GIT_HOOKS_DIR/$hook"
        chmod +x "$GIT_HOOKS_DIR/$hook"
        echo "✓ Installed $hook hook"
    else
        echo "⚠ Warning: $hook hook not found in $HOOKS_DIR"
    fi
done

echo ""
echo "Git hooks installed successfully!"
echo ""
echo "The following hooks are now active:"
echo "  • pre-commit: Scans for secrets and sensitive data"
echo "  • commit-msg: Enforces Conventional Commits format"
echo ""
echo "To bypass hooks (not recommended): git commit --no-verify"
