#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "$0")/../dotfiles" && pwd)"

echo "--> Dotfiles (symlinking from $DOTFILES_DIR)"

# Link ~/. dotfiles
for file in "$DOTFILES_DIR"/.*; do
  name=$(basename "$file")
  [[ "$name" == "." || "$name" == ".." ]] && continue


  if [ -f "$HOME/$name" ] && [ ! -L "$HOME/$name" ]; then
    backup_file="$HOME/${name}.bak"
    if [ -e "$backup_file" ]; then
      timestamp=$(date +%Y%m%d%H%M%S)
      backup_file="$HOME/${name}.bak.$timestamp"
    fi
    echo "    Backing up $HOME/$name → $backup_file"
    mv "$HOME/$name" "$backup_file"
  fi

  ln -sf "$file" "$HOME/$name"
  echo "    Linked ~/$name"
done


# Link ~/.config/* files and copy app config subdirectories.
if [ -d "$DOTFILES_DIR/config" ]; then
  mkdir -p "$HOME/.config"

  for file in "$DOTFILES_DIR/config"/*; do
    [ -f "$file" ] || continue
    name=$(basename "$file")
    target="$HOME/.config/$name"

    if [ -f "$target" ] && [ ! -L "$target" ]; then
      backup_file="${target}.bak"
      if [ -e "$backup_file" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_file="${target}.bak.$timestamp"
      fi
      echo "    Backing up $target → $backup_file"
      mv "$target" "$backup_file"
    fi

    ln -sf "$file" "$target"
    echo "    Linked ~/.config/$name"
  done

  for dir in "$DOTFILES_DIR/config"/*/; do
    name=$(basename "$dir")
    target="$HOME/.config/$name"

    if [ -d "$target" ] && [ ! -L "$target" ]; then
      backup_dir="${target}.bak"
      if [ -e "$backup_dir" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_dir="${target}.bak.$timestamp"
      fi
      echo "    Backing up $target → $backup_dir"
      mv "$target" "$backup_dir"
    fi

    cp -R "$dir" "$target"
    echo "    Copied ~/.config/$name"
  done
fi

# Link safe Pi settings, extensions, and themes (never auth or sessions).
PI_AGENT_DIR="$DOTFILES_DIR/pi/agent"
if [ -d "$PI_AGENT_DIR" ]; then
  mkdir -p "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/themes"

  for file in "$PI_AGENT_DIR"/*.json "$PI_AGENT_DIR/extensions"/*.ts "$PI_AGENT_DIR/themes"/*.json; do
    [ -f "$file" ] || continue

    case "$file" in
      "$PI_AGENT_DIR/extensions"/*) target="$HOME/.pi/agent/extensions/$(basename "$file")" ;;
      "$PI_AGENT_DIR/themes"/*) target="$HOME/.pi/agent/themes/$(basename "$file")" ;;
      *) target="$HOME/.pi/agent/$(basename "$file")" ;;
    esac

    if [ -f "$target" ] && [ ! -L "$target" ]; then
      backup_file="${target}.bak"
      if [ -e "$backup_file" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_file="${target}.bak.$timestamp"
      fi
      echo "    Backing up $target → $backup_file"
      mv "$target" "$backup_file"
    fi

    ln -sf "$file" "$target"
    echo "    Linked ${target/#$HOME/~}"
  done
fi

# Copy ~/Library/Application Support/* app config dirs
LIBRARY_APP_SUPPORT="$DOTFILES_DIR/Library/Application Support"
if [ -d "$LIBRARY_APP_SUPPORT" ]; then
  mkdir -p "$HOME/Library/Application Support"
  for dir in "$LIBRARY_APP_SUPPORT"/*/; do
    name=$(basename "$dir")
    target="$HOME/Library/Application Support/$name"

    if [ -d "$target" ] && [ ! -L "$target" ]; then
      backup_dir="${target}.bak"
      if [ -e "$backup_dir" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_dir="${target}.bak.$timestamp"
      fi
      echo "    Backing up $target → $backup_dir"
      mv "$target" "$backup_dir"
    fi

    cp -R "$dir" "$target"
    echo "    Copied ~/Library/Application Support/$name"
  done
fi

echo "    Done."
