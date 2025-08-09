#!/bin/bash
set -euo pipefail

# === CONFIG ===
CONFIG_FILE="$HOME/.zen_sync_config.json"
FILES=("places.sqlite" "places.sqlite-shm" "places.sqlite-wal" "sessionstore.jsonlz4")
SESSION_DIR="sessionbackups"
SESSIONSTORE_BACKUPS_DIR="sessionstore-backups"

# === CONFIGURATION MANAGEMENT ===
get_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        cat "$CONFIG_FILE"
    else
        echo "null"
    fi
}

save_config() {
    local repo_url="$1"
    local repo_dir="$2"
    
    cat > "$CONFIG_FILE" << EOF
{
    "repositoryUrl": "$repo_url",
    "repositoryDir": "$repo_dir",
    "lastBackup": null,
    "lastRestore": null
}
EOF
    echo "Configuration saved"
}

initialize_repository() {
    local action="$1"
    
    echo "Repository Setup for $action"
    echo "You need to provide a Git repository URL for your backups."
    echo "Examples:"
    echo "  SSH: git@github.com:username/zen-browser-backup.git"
    echo "  HTTPS: https://github.com/username/zen-browser-backup.git"
    
    while true; do
        read -p "Enter your backup repository URL: " repo_url
        if [[ -z "$repo_url" ]]; then
            echo "Repository URL cannot be empty"
            continue
        fi
        
        if [[ ! "$repo_url" =~ ^(https://|git@).*\.git$ ]]; then
            echo "Invalid repository URL format"
            continue
        fi
        
        break
    done
    
    repo_name=$(basename "$repo_url" .git)
    repo_dir="/tmp/zen-backup-$repo_name"
    
    save_config "$repo_url" "$repo_dir"
    echo "{\"Url\":\"$repo_url\",\"Dir\":\"$repo_dir\"}"
}

# === ZEN BROWSER PROFILE DETECTION ===
get_zen_profile_paths() {
    local profiles=()
    
    # Check for regular Zen Browser profiles
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - check flatpak path
        zen_base="$HOME/.var/app/app.zen_browser.zen/.zen"
        ini_path="$zen_base/profiles.ini"
        
        if [[ -f "$ini_path" ]]; then
            profile_path=$(grep "^Path=" "$ini_path" | head -1 | cut -d'=' -f2)
            is_relative=$(grep "^IsRelative=" "$ini_path" | head -1 | cut -d'=' -f2)
            
            if [[ "$is_relative" == "1" ]]; then
                profiles+=("Regular:$zen_base/$profile_path")
            else
                profiles+=("Regular:$profile_path")
            fi
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        zen_base="$HOME/Library/Application Support/Zen"
        ini_path="$zen_base/profiles.ini"
        
        if [[ -f "$ini_path" ]]; then
            profile_path=$(grep "^Path=" "$ini_path" | head -1 | cut -d'=' -f2)
            is_relative=$(grep "^IsRelative=" "$ini_path" | head -1 | cut -d'=' -f2)
            
            if [[ "$is_relative" == "1" ]]; then
                profiles+=("Regular:$zen_base/$profile_path")
            else
                profiles+=("Regular:$profile_path")
            fi
        fi
    fi
    
    # Check for Twilight Zen Browser profiles on Windows
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
        twilight_profiles_path="$APPDATA/zen/Profiles"
        if [[ -d "$twilight_profiles_path" ]]; then
            for dir in "$twilight_profiles_path"/*; do
                if [[ -d "$dir" ]]; then
                    profile_name=$(basename "$dir")
                    profiles+=("Twilight ($profile_name):$dir")
                fi
            done
        fi
    else
        # Check for Twilight Zen Browser profiles on Linux/macOS
        twilight_profiles_path="$HOME/.zen/profiles"
        if [[ -d "$twilight_profiles_path" ]]; then
            for dir in "$twilight_profiles_path"/*; do
                if [[ -d "$dir" ]]; then
                    profile_name=$(basename "$dir")
                    profiles+=("Twilight ($profile_name):$dir")
                fi
            done
        fi
    fi
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "Error: No Zen Browser profiles found. Make sure Zen Browser is installed and has been run at least once."
        exit 1
    fi
    
    printf '%s\n' "${profiles[@]}"
}

select_profile() {
    local profiles=()
    local profile_names=()
    local profile_paths=()
    
    # Read profiles into arrays
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            profiles+=("$line")
            profile_names+=("$(echo "$line" | cut -d':' -f1)")
            profile_paths+=("$(echo "$line" | cut -d':' -f2)")
        fi
    done < <(get_zen_profile_paths)
    
    if [[ ${#profiles[@]} -eq 1 ]]; then
        echo "Found 1 profile: ${profile_names[0]}"
        echo "${profile_paths[0]}"
        return
    fi
    
    echo "Found ${#profiles[@]} Zen Browser profiles:"
    for i in "${!profile_names[@]}"; do
        echo "  [$((i+1))] ${profile_names[i]}"
        echo "      ${profile_paths[i]}"
    done
    
    while true; do
        read -p "Select profile (1-${#profiles[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#profiles[@]} ]]; then
            echo "${profile_paths[$((selection-1))]}"
            return
        fi
        echo "Invalid selection. Please enter a number between 1 and ${#profiles[@]}."
    done
}

# === UTILITY FUNCTIONS ===
test_prerequisites() {
    if ! command -v git &> /dev/null; then
        echo "Git not found. Please install Git"
        exit 1
    fi
    
    if ! command -v tar &> /dev/null; then
        echo "tar not found. Please install tar"
        exit 1
    fi
}

# === BACKUP FUNCTION ===
invoke_backup() {
    echo "Starting Zen Browser Backup..."
    
    test_prerequisites
    
    config=$(get_config)
    if [[ "$config" == "null" ]]; then
        config=$(initialize_repository "Backup")
    fi
    
    repo_url=$(echo "$config" | jq -r '.repositoryUrl')
    repo_dir=$(echo "$config" | jq -r '.repositoryDir')
    full_path=$(select_profile)
    
    echo "Selected Zen Profile: $full_path"
    
    # Clean up any existing repo directory
    if [[ -d "$repo_dir" ]]; then
        rm -rf "$repo_dir"
    fi
    
    # Clone or create repository
    echo "Setting up repository..."
    
    # Try to clone first (repo exists)
    if git clone "$repo_url" "$repo_dir" 2>/dev/null; then
        echo "Repository cloned successfully"
    else
        # Repo doesn't exist or clone failed, initialize new
        mkdir -p "$repo_dir"
        cd "$repo_dir"
        
        git init
        git remote add origin "$repo_url"
        
        # Create initial commit
        echo "# Zen Browser Backups" > README.md
        git add README.md
        git commit -m "Initial commit"
        
        # Push to set up remote
        git push -u origin master 2>/dev/null || git push -u origin main 2>/dev/null
    fi
    
    cd "$repo_dir"
    
    changed=false
    
    # Backup individual files
    for file in "${FILES[@]}"; do
        src="$full_path/$file"
        dst="$repo_dir/$file"
        
        if [[ -f "$src" ]]; then
            echo "Copying $file..."
            cp "$src" "$dst"
            changed=true
        else
            echo "File not found: $file"
        fi
    done
    
    # Backup folders
    for folder in "$SESSION_DIR" "$SESSIONSTORE_BACKUPS_DIR"; do
        src_folder="$full_path/$folder"
        tar_file="$repo_dir/$folder.tar.gz"
        
        if [[ -d "$src_folder" ]]; then
            echo "Archiving $folder..."
            tar -czf "$tar_file" -C "$full_path" "$folder"
            changed=true
        else
            echo "Folder not found: $folder"
        fi
    done
    
    if [[ "$changed" == true ]]; then
        echo "Pushing to repository..."
        git add .
        git commit -m "Zen Browser backup - $(date '+%Y-%m-%d %H:%M:%S')"
        git push
        
        if [[ $? -eq 0 ]]; then
            echo "Backup completed successfully!"
            # Update config
            jq --arg last_backup "$(date '+%Y-%m-%d %H:%M:%S')" '.lastBackup = $last_backup' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"
        else
            echo "Failed to push to repository"
            exit 1
        fi
    else
        echo "No files found to backup"
    fi
    
    # Cleanup
    cd /
    rm -rf "$repo_dir"
}

# === RESTORE FUNCTION ===
invoke_restore() {
    echo "Starting Zen Browser Restore..."
    
    test_prerequisites
    
    config=$(get_config)
    if [[ "$config" == "null" ]]; then
        config=$(initialize_repository "Restore")
    fi
    
    repo_url=$(echo "$config" | jq -r '.repositoryUrl')
    repo_dir=$(echo "$config" | jq -r '.repositoryDir')
    full_path=$(get_zen_profile_path)
    
    echo "Zen Profile: $full_path"
    
    # Clean up any existing repo directory
    if [[ -d "$repo_dir" ]]; then
        rm -rf "$repo_dir"
    fi
    
    # Clone repository
    echo "Cloning backup repository..."
    git clone "$repo_url" "$repo_dir"
    
    cd "$repo_dir"
    
    # Restore individual files
    for file in "${FILES[@]}"; do
        src="$repo_dir/$file"
        dst="$full_path/$file"
        
        if [[ -f "$src" ]]; then
            echo "Restoring $file..."
            
            # Backup existing file
            if [[ -f "$dst" ]]; then
                bak_file="$dst.bak"
                echo "Backing up existing $file to $(basename "$bak_file")"
                mv "$dst" "$bak_file"
            fi
            
            cp "$src" "$dst"
        else
            echo "Backup not found: $file"
        fi
    done
    
    # Restore folders
    for folder in "$SESSION_DIR" "$SESSIONSTORE_BACKUPS_DIR"; do
        src="$repo_dir/$folder.tar.gz"
        dst_folder="$full_path/$folder"
        
        if [[ -f "$src" ]]; then
            echo "Restoring $folder..."
            
            # Backup existing folder
            if [[ -d "$dst_folder" ]]; then
                bak_folder="$dst_folder.bak"
                echo "Backing up existing $folder to $(basename "$bak_folder")"
                if [[ -d "$bak_folder" ]]; then
                    rm -rf "$bak_folder"
                fi
                mv "$dst_folder" "$bak_folder"
            fi
            
            tar -xzf "$src" -C "$full_path"
        else
            echo "Backup not found: $folder.tar.gz"
        fi
    done
    
    echo "Restore completed successfully!"
    
    # Update config
    jq --arg last_restore "$(date '+%Y-%m-%d %H:%M:%S')" '.lastRestore = $last_restore' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"
    
    # Cleanup
    cd /
    rm -rf "$repo_dir"
}

# === MAIN ===
if [[ $# -eq 0 ]]; then
    echo "Zen Browser Profile Backup & Restore (No GPG)"
    echo "Usage: $0 {backup|restore}"
    echo ""
    echo "Prerequisites:"
    echo "  1. Have a Git repository ready for backups"
    echo "  2. Install jq: sudo apt install jq (Linux) or brew install jq (macOS)"
    exit 1
fi

case "$1" in
    backup)
        invoke_backup
        ;;
    restore)
        invoke_restore
        ;;
    *)
        echo "Usage: $0 {backup|restore}"
        exit 1
        ;;
esac
