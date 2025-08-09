#!/bin/bash

# Zen Browser Auto-Sync Script
# Watches for changes and automatically syncs to Git

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZEN_SYNC_SCRIPT="$SCRIPT_DIR/zen-sync-no-gpg.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Function to check if inotify-tools is available
check_inotify() {
    if ! command -v inotifywait &> /dev/null; then
        print_error "inotify-tools not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt install inotify-tools"
        echo "  Arch Linux: sudo pacman -S inotify-tools"
        echo "  Fedora: sudo dnf install inotify-tools"
        exit 1
    fi
}

# Function to get Zen profile path
get_zen_profile() {
    # Source the profile selection function from main script
    if [[ -f "$ZEN_SYNC_SCRIPT" ]]; then
        # Extract profile path using the main script
        profile_path=$("$ZEN_SYNC_SCRIPT" backup 2>/dev/null | grep -o '/.*zen.*' | head -1)
        if [[ -n "$profile_path" ]]; then
            echo "$profile_path"
            return 0
        fi
    fi
    
    # Fallback to manual selection
    echo "Please select your Zen profile:"
    if [[ -d "$HOME/.var/app/app.zen_browser.zen/.zen" ]]; then
        echo "1) Regular Zen (Flatpak): $HOME/.var/app/app.zen_browser.zen/.zen"
    fi
    if [[ -d "$HOME/.zen/profiles" ]]; then
        for dir in "$HOME/.zen/profiles"/*; do
            if [[ -d "$dir" ]]; then
                echo "2) Twilight ($(basename "$dir")): $dir"
            fi
        done
    fi
    
    read -p "Enter profile number: " choice
    case $choice in
        1) echo "$HOME/.var/app/app.zen_browser.zen/.zen" ;;
        2) echo "$HOME/.zen/profiles"/* | head -1 ;;
        *) echo "$HOME/.var/app/app.zen_browser.zen/.zen" ;;
    esac
}

# Function to perform backup
perform_backup() {
    print_status "Performing automatic backup..."
    "$ZEN_SYNC_SCRIPT" backup
}

# Function to perform restore
perform_restore() {
    print_status "Performing automatic restore..."
    "$ZEN_SYNC_SCRIPT" restore
}

# Function to watch for file changes
watch_mode() {
    local profile_path="$1"
    local watch_dir="$profile_path"
    
    print_status "Starting watch mode for: $watch_dir"
    print_status "Monitoring changes to places.sqlite, sessionstore.jsonlz4, and sessionstore-backups/"
    
    # Files to watch
    files_to_watch=(
        "$watch_dir/places.sqlite"
        "$watch_dir/sessionstore.jsonlz4"
        "$watch_dir/sessionstore-backups"
    )
    
    # Check if files exist
    for file in "${files_to_watch[@]}"; do
        if [[ -e "$file" ]]; then
            print_status "Watching: $file"
        fi
    done
    
    # Start watching
    while true; do
        if command -v inotifywait &> /dev/null; then
            # Use inotifywait for efficient watching
            inotifywait -e modify,create,delete -r "${files_to_watch[@]}" 2>/dev/null
            print_status "Change detected, backing up..."
            perform_backup
            sleep 30  # Prevent rapid successive backups
        else
            # Fallback: check every 60 seconds
            print_status "Checking for changes..."
            if [[ -f "$watch_dir/places.sqlite" ]]; then
                current_hash=$(find "$watch_dir" -name "places.sqlite" -o -name "sessionstore.jsonlz4" -o -path "*/sessionstore-backups/*" | xargs md5sum 2>/dev/null || echo "")
                if [[ "$current_hash" != "$last_hash" ]]; then
                    print_status "Change detected, backing up..."
                    perform_backup
                    last_hash="$current_hash"
                fi
            fi
            sleep 60
        fi
    done
}

# Function to schedule periodic sync
schedule_mode() {
    local interval="$1"
    local profile_path="$2"
    
    print_status "Starting scheduled sync every $interval minutes"
    
    while true; do
        print_status "Scheduled backup at $(date)"
        perform_backup
        sleep $((interval * 60))
    done
}

# Function to push changes to Git
push_changes() {
    print_status "Pushing changes to GitHub..."
    "$ZEN_SYNC_SCRIPT" backup
}

# Function to pull changes from Git
pull_changes() {
    print_status "Pulling changes from GitHub..."
    "$ZEN_SYNC_SCRIPT" restore
}

# Main function
main() {
    local mode="$1"
    local interval="${2:-60}"  # Default 60 minutes for schedule mode
    
    # Check if main script exists
    if [[ ! -f "$ZEN_SYNC_SCRIPT" ]]; then
        print_error "Main script not found: $ZEN_SYNC_SCRIPT"
        exit 1
    fi
    
    # Get Zen profile path
    zen_profile=$(get_zen_profile)
    print_status "Using Zen profile: $zen_profile"
    
    case "$mode" in
        "watch")
            check_inotify
            watch_mode "$zen_profile"
            ;;
        "schedule")
            schedule_mode "$interval" "$zen_profile"
            ;;
        "push")
            push_changes
            ;;
        "pull")
            pull_changes
            ;;
        *)
            echo "Usage: $0 {watch|schedule [interval]|push|pull}"
            echo "  watch     - Monitor files for changes and auto-backup"
            echo "  schedule  - Backup every N minutes (default: 60)"
            echo "  push      - Manually push changes to GitHub"
            echo "  pull      - Manually pull changes from GitHub"
            echo ""
            echo "Examples:"
            echo "  $0 watch"
            echo "  $0 schedule 30"
            echo "  $0 push"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
