#!/bin/bash
# selog.sh - A script to generate Confluence-formatted logs and manage release notes

# Function to copy text to the clipboard
copy_to_clipboard() {
  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard
  elif command -v xsel >/dev/null 2>&1; then
    xsel --clipboard --input
  elif command -v clip >/dev/null 2>&1; then
    clip
  else
    echo "No clipboard utility found. Please install pbcopy, xclip, xsel, or clip."
    return 1
  fi
}

# Function to open a URL in the default web browser
open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url"
  elif command -v open >/dev/null 2>&1; then
    open "$url"
  else
    echo "Cannot open URL: $url"
    return 1
  fi
}

# Function to generate a Confluence-formatted log
generate_confluence_log() {
  # Check if a commit hash or ref is provided
  local commit_start
  if [[ -n "$1" ]]; then
    commit_start="$1"
  else
    commit_start="$(git rev-list --max-parents=0 HEAD)" # First commit
  fi

  # Define the commit range from the starting commit to HEAD
  local commit_range="$commit_start..HEAD"

  # Output the table header
  echo "|hash|subject|tickets|"
  echo "|---|-----------|------|"

  # Get commit log and iterate over each commit hash
  git log "$commit_range" --no-merges --format='%H' | while read -r commit; do
    # Get commit hash, subject, and body
    local hash="$commit"
    local subject
    subject=$(git log -n 1 --format=%s "$commit")
    local body
    body=$(git log -n 1 --format=%B "$commit")

    # Initialize tickets variable
    local tickets=""

    # Search for 'Tickets:' tag in the commit body
    while read -r ticket_line; do
      # Extract ticket number(s) after 'Tickets:'
      local ticket_list
      ticket_list=$(echo "$ticket_line" | cut -d ':' -f 2)

      # Split ticket_list into individual tickets
      IFS=',' read -r -a ticket_array <<<"$ticket_list"
      for ticket in "${ticket_array[@]}"; do
        ticket=$(echo "$ticket" | xargs) # Trim whitespace
        local ticket_url="${TICKET_URL_BASE}/$ticket"
        if [[ -n "$tickets" ]]; then
          tickets+=" , "
        fi
        tickets+="$ticket_url"
      done
    done <<< "$(echo "$body" | grep -i 'Tickets:')"

    # Output formatted row for Confluence
    echo "|$hash|$subject| $tickets |"
  done
}

# Main function
selog() {
  # Initialize variables
  major_version=""
  hash=""
  auto_accept_version=false

  # Configuration paths
  CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
  SELOG_CONFIG_DIR="$CONFIG_HOME/selog"
  REPOS_DIR="$SELOG_CONFIG_DIR/repos"
  ticket_url_file="$SELOG_CONFIG_DIR/ticket_url.conf"

  # Ensure the config directories exist
  mkdir -p "$REPOS_DIR"

  # Check if the ticket URL configuration file exists
  if [ -f "$ticket_url_file" ]; then
    # Read the ticket URL base from the configuration file
    TICKET_URL_BASE=$(cat "$ticket_url_file")
  else
    # Configuration file does not exist
    echo "No ticket URL configuration found."
    echo "Enter the base URL for tickets (e.g., https://example.atlassian.net/browse):"
    read -r TICKET_URL_BASE

    if [ -z "$TICKET_URL_BASE" ]; then
      echo "Ticket URL base is required."
      exit 1
    fi

    # Save the URL to the configuration file
    echo "$TICKET_URL_BASE" >"$ticket_url_file"
  fi

  echo "Ticket URL base is set to: $TICKET_URL_BASE"

  # Function to display help message
  show_help() {
    echo "Usage: selog [OPTIONS] [<hash>]"
    echo
    echo "Generates a Confluence-formatted log of commits from a starting hash to HEAD."
    echo "Copies the output to the clipboard and optionally opens the release notes URL."
    echo
    echo "Options:"
    echo "  -v, --version <version>    Specify the major version number."
    echo "  -y                         Automatically accept the detected version without prompting."
    echo "  --help                     Display this help message and exit."
    echo
    echo "Arguments:"
    echo "  <hash>                     Starting commit hash or tag to generate the log from."
    echo "                             If not provided, an interactive selection (using fzf) is used."
    echo
    echo "Notes:"
    echo "  - The version is determined automatically based on the current branch name"
    echo "    (if it contains a version number) or the highest version tag."
    echo "  - The generated log is copied to the clipboard."
    echo "  - Requires git and fzf (if interactive selection is used)."
    echo
    echo "Examples:"
    echo "  selog --version 1.2        Use major version 1.2 and select starting hash interactively."
    echo "  selog abc1234              Generate log from commit abc1234 with auto-detected version."
    echo "  selog -y                   Automatically accept the detected version."
    echo "  selog --help               Display this help message and exit."
  }

  # Parse options
  while [ $# -gt 0 ]; do
    case "$1" in
    -v=* | --version=*)
      major_version="${1#*=}"
      ;;
    -v | --version)
      shift
      major_version="$1"
      ;;
    -y)
      auto_accept_version=true
      ;;
    --help)
      show_help
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use 'selog --help' for usage information."
      exit 1
      ;;
    *)
      # Positional argument (hash)
      if [ -z "$hash" ]; then
        hash="$1"
      else
        echo "Too many arguments."
        echo "Use 'selog --help' for usage information."
        exit 1
      fi
      ;;
    esac
    shift
  done

  if [ -z "$hash" ]; then
    if command -v fzf >/dev/null 2>&1; then
      # Use fzf to select a commit hash or tag with advanced preview
      hash=$(git log --graph --color=always \
        --format="%C(yellow)%h %C(green)%d %C(reset)%s %C(bold)%cr" --abbrev-commit --date=relative |
        fzf --ansi --no-sort --reverse --tiebreak=index \
          --preview 'git show --color=always $(echo {} | awk "{print \$1}")' \
          --preview-window=right:60% | grep -Eo '\b[0-9a-f]{7,40}\b' | head -n 1)
      if [ -z "$hash" ]; then
        echo "No commit or tag selected."
        exit 1
      fi
    else
      echo "Error: fzf is not installed and no hash was provided."
      echo "Use 'selog --help' for usage information."
      exit 1
    fi
  fi

  # If major_version is set via --version or -v, use it
  if [ -n "$major_version" ]; then
    # Use the provided major_version
    :
  else
    # Existing logic to determine major_version
    # Get current Git branch name
    current_branch=$(git rev-parse --abbrev-ref HEAD)

    # Try to extract version from branch name
    branch_version=$(echo "$current_branch" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')

    if [ -n "$branch_version" ]; then
      # If version is found in branch name, use it
      major_version=$(echo "$branch_version" | awk -F. '{print $1"."$2}')
    else
      # No version in branch name, proceed as before
      # Get the highest version tag
      highest_tag=$(git tag --no-column --sort=-v:refname | head -n1)
      if [ -z "$highest_tag" ]; then
        major_version="0.0"
      else
        # Extract the major version number (e.g., '8.0')
        version_numbers=$(echo "$highest_tag" | sed 's/^[^0-9]*//')
        major_version=$(echo "$version_numbers" | awk -F. '{print $1"."$2}')
        if [ -z "$major_version" ]; then
          major_version="0.0"
        fi
      fi
    fi
  fi

  # Prompt the user to confirm or change the major version if auto_accept_version is not set
  if [ "$auto_accept_version" = false ]; then
    echo "Current major version is ${major_version}. Is this correct? (y/n, Enter for yes): "
    read -r confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "" ]; then
      echo "Enter the correct major version: "
      read -r major_version

      if [ -z "$major_version" ]; then
        echo "Major version is required."
        exit 1
      fi
    fi
  fi

  # Get today's date in YYYYMMDD format
  date_str=$(date +'%Y%m%d')

  # Construct the version string
  version="${major_version}.${date_str}.1"

  # Create a temporary file
  tmpfile=$(mktemp /tmp/se_log_output.XXXXXX.md)

  # Run the command and prepend the version string as H1
  {
    echo "# ${version}"
    echo
    # se-project log --format confluence --from="$hash"
    generate_confluence_log "$hash"
  } >"$tmpfile"

  # Copy the output to the clipboard
  cat "$tmpfile" | copy_to_clipboard

  # Display the output using mdv if available, else just cat
  if command -v mdv >/dev/null 2>&1; then
    mdv "$tmpfile"
  else
    cat "$tmpfile"
  fi

  # Clean up the temporary file
  rm "$tmpfile"

  # Ask if the user wants to open the release notes
  echo "Do you want to open the release notes in your browser? (y/n, Enter for no): "
  read -r open_releasenotes
  if [ "$open_releasenotes" = "y" ] || [ "$open_releasenotes" = "Y" ]; then
    # Determine the release notes URL

    # Get the repository URL
    repo_url=$(git config --get remote.origin.url)

    # Generate a hash of the repo URL to use as the config filename
    repo_hash=$(echo -n "$repo_url" | sha256sum | cut -d ' ' -f1)

    # Configuration file path
    config_file="$REPOS_DIR/$repo_hash.conf"

    # Check if the configuration file exists
    if [ -f "$config_file" ]; then
      # Read the URL from the configuration file
      release_notes_url=$(cat "$config_file")
    else
      # Configuration file does not exist
      echo "No configuration found for this repository."
      echo "Would you like to add one? (y/n, Enter for yes): "
      read -r add_config
      if [ "$add_config" = "y" ] || [ "$add_config" = "Y" ] || [ "$add_config" = "" ]; then
        echo "Enter the URL to open for release notes:"
        read -r release_notes_url

        # Save the URL to the configuration file
        mkdir -p "$(dirname "$config_file")"
        echo "$release_notes_url" >"$config_file"
      else
        # User does not want to add configuration
        echo "No URL configured. Cannot open release notes."
        release_notes_url=""
      fi
    fi

    # Check if the ticket URL configuration file exists
    if [ -f "$ticket_url_file" ]; then
      # Read the ticket URL base from the configuration file
      TICKET_URL_BASE=$(cat "$ticket_url_file")
    else
      # Configuration file does not exist
      echo "No ticket URL configuration found."
      echo "Would you like to add one? (y/n, Enter for yes): "
      read -r add_ticket_url_config
      if [ "$add_ticket_url_config" = "y" ] || [ "$add_ticket_url_config" = "Y" ] || [ "$add_ticket_url_config" = "" ]; then
        echo "Enter the base URL for tickets (e.g., https://example.atlassian.net/browse):"
        read -r TICKET_URL_BASE

        # Save the URL to the configuration file
        echo "$TICKET_URL_BASE" >"$ticket_url_file"
      fi
    fi

    # Open the URL in the default web browser
    if [ -n "$release_notes_url" ]; then
      open_url "$release_notes_url"
    else
      echo "No URL configured. Cannot open release notes."
    fi
  fi
}

# Execute the main function with all provided arguments
selog "$@"