#!/bin/bash

# install.sh - Installation script for selog.sh

# Function to display messages
info() {
  echo -e "\033[1;34m[INFO]\033[0m $1"
}

error() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
}

# Set variables
REPO_URL="git@github.com:JonasWijne/selog.git"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SELOG_CONFIG_DIR="$CONFIG_HOME/selog"
REPOS_DIR="$SELOG_CONFIG_DIR/repos"
INSTALL_DIR="$SELOG_CONFIG_DIR/selog_repo"
BIN_DIR="$HOME/bin"
SCRIPT_NAME="selog.sh"
LINK_NAME="selog"

# Clone the repository into the config directory
if [ -d "$INSTALL_DIR/.git" ]; then
  info "Repository already cloned. Pulling latest changes..."
  git -C "$INSTALL_DIR" pull
else
  info "Cloning repository into $INSTALL_DIR..."
  git clone "$REPO_URL" "$INSTALL_DIR" || { error "Failed to clone repository."; exit 1; }
fi

# Make the script executable
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

# Create bin directory if it doesn't exist
if [ ! -d "$BIN_DIR" ]; then
  info "Creating bin directory at $BIN_DIR..."
  mkdir -p "$BIN_DIR"
fi

# Create a symlink in the bin directory
info "Creating symlink $BIN_DIR/$LINK_NAME -> $INSTALL_DIR/$SCRIPT_NAME"
ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$BIN_DIR/$LINK_NAME"

info "Installation complete."

# Check if ~/bin is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo
  info "Adding $BIN_DIR to your PATH..."
  SHELL_CONFIG="$HOME/.bashrc"
  if [ -n "$ZSH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ]; then
    SHELL_CONFIG="$HOME/.bashrc"
  fi
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$SHELL_CONFIG"
  info "Please restart your terminal or run 'source $SHELL_CONFIG' to update your PATH."
fi
