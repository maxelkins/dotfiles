#!/usr/bin/env bash
set -e

echo "--> macOS settings"

# Hostname (asked only at a terminal; headless runs keep the current name)
HOSTNAME=""
if [ "${DOT_HEADLESS:-}" = 1 ] || [ ! -t 0 ]; then
  echo "    Skipping the computer name prompt (no interactive terminal)"
else
  read -rp "    Computer name (e.g. max-macbook, leave blank to skip): " HOSTNAME
fi
if [ -n "$HOSTNAME" ]; then
  sudo scutil --set ComputerName  "$HOSTNAME"
  sudo scutil --set HostName      "$HOSTNAME"
  sudo scutil --set LocalHostName "$HOSTNAME"
  echo "    Hostname set to: $HOSTNAME"
fi

# Dock
echo "    Configuring Dock..."
defaults write com.apple.dock tilesize -int 64
defaults write com.apple.dock orientation -string "right"
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false

# Finder
echo "    Configuring Finder..."
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder AppleShowAllFiles -bool false        # hidden files off
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv" # list view
defaults write com.apple.finder NewWindowTarget -string "PfHm"      # open to Home
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf" # search current folder
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Screenshots — save to ~/Desktop/Screenshots
echo "    Configuring screenshots..."
mkdir -p "$HOME/Screenshots"
defaults write com.apple.screencapture location "$HOME/Screenshots"
defaults write com.apple.screencapture type -string "png"

# Trackpad
echo "    Configuring trackpad..."
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool false       # tap to click off
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -bool true
defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool false
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool false
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false  # non-natural scroll

# Menu bar clock — show day of week + AM/PM, no date
echo "    Configuring menu bar clock..."
defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock ShowDate -bool false
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true

# Appearance — auto dark/light mode
echo "    Configuring appearance..."
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool true

# Apply changes
killall Dock
killall Finder
killall SystemUIServer 2>/dev/null || true

echo "    Done."
