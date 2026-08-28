#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "================================================"
echo "  Mac Setup"
echo "================================================"

bash "$SCRIPT_DIR/scripts/homebrew.sh"
bash "$SCRIPT_DIR/scripts/git-hooks.sh"
bash "$SCRIPT_DIR/scripts/ohmyzsh.sh"
bash "$SCRIPT_DIR/scripts/dotfiles.sh"
bash "$SCRIPT_DIR/scripts/macos.sh"
bash "$SCRIPT_DIR/scripts/dock.sh"

echo ""
echo "================================================"
echo "  Done! Restart your terminal to apply changes."
echo "================================================"
