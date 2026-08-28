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

    # Herdr keeps runtime state beside config.toml, so link only tracked files.
    if [ "$name" = "herdr" ]; then
      mkdir -p "$target"
      for file in "$dir"*; do
        [ -f "$file" ] || continue
        target_file="$target/$(basename "$file")"

        if [ -f "$target_file" ] && [ ! -L "$target_file" ]; then
          backup_file="${target_file}.bak"
          if [ -e "$backup_file" ]; then
            timestamp=$(date +%Y%m%d%H%M%S)
            backup_file="${target_file}.bak.$timestamp"
          fi
          echo "    Backing up $target_file → $backup_file"
          mv "$target_file" "$backup_file"
        fi

        ln -sf "$file" "$target_file"
        echo "    Linked ~/.config/herdr/$(basename "$file")"
      done
      continue
    fi

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

# Link shared agent skills from the repository. Keep harness-specific skills
# alongside them, and expose the shared set to Claude Code explicitly.
AGENTS_DIR="$DOTFILES_DIR/agents"
if [ -d "$AGENTS_DIR/skills" ]; then
  mkdir -p "$HOME/.agents"

  target="$HOME/.agents/skills"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    backup_dir="${target}.bak"
    if [ -e "$backup_dir" ]; then
      timestamp=$(date +%Y%m%d%H%M%S)
      backup_dir="${target}.bak.$timestamp"
    fi
    echo "    Backing up $target → $backup_dir"
    mv "$target" "$backup_dir"
  fi

  ln -sfn "$AGENTS_DIR/skills" "$target"
  echo "    Linked ~/.agents/skills"

  if [ -f "$AGENTS_DIR/.skill-lock.json" ]; then
    target="$HOME/.agents/.skill-lock.json"
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      backup_file="${target}.bak"
      if [ -e "$backup_file" ]; then
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_file="${target}.bak.$timestamp"
      fi
      echo "    Backing up $target → $backup_file"
      mv "$target" "$backup_file"
    fi

    ln -sf "$AGENTS_DIR/.skill-lock.json" "$target"
    echo "    Linked ~/.agents/.skill-lock.json"
  fi

  mkdir -p "$HOME/.claude/skills"
  for skill in "$AGENTS_DIR/skills"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    target="$HOME/.claude/skills/$name"

    # Preserve Claude-only skills. Shared skill links are safe to refresh.
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      continue
    fi

    ln -sfn "$HOME/.agents/skills/$name" "$target"
  done
  echo "    Linked shared skills into ~/.claude/skills"
fi

# Link safe Pi settings, extensions, and themes (never auth or sessions).
PI_AGENT_DIR="$DOTFILES_DIR/pi/agent"
if [ -d "$PI_AGENT_DIR" ]; then
  mkdir -p "$HOME/.pi/agent/extensions" "$HOME/.pi/agent/themes"

  for file in "$PI_AGENT_DIR"/*.json "$PI_AGENT_DIR"/*.md "$PI_AGENT_DIR/extensions"/*.ts "$PI_AGENT_DIR/themes"/*.json; do
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
