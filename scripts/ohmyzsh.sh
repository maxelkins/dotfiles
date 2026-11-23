#!/usr/bin/env bash
set -e

echo "--> Oh My Zsh"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "    Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" -- --unattended --keep-zshrc
  echo "    Done."
else
  echo "    Oh My Zsh already installed, skipping."
fi
