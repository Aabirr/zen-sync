#!/bin/bash

# Debug the actual profile detection
set -e

# Test get_zen_profile_paths
zen_base="$HOME/.zen"
ini_path="$zen_base/profiles.ini"

echo "=== DEBUG: Profile Detection ==="
echo "Checking profiles.ini at: $ini_path"
echo "File exists: $(test -f "$ini_path" && echo "YES" || echo "NO")"

if [[ -f "$ini_path" ]]; then
    echo "=== profiles.ini content ==="
    cat "$ini_path"
    echo ""
    
    echo "=== Detected profiles ==="
    profiles=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^Path= ]]; then
            profile_path=$(echo "$line" | cut -d'=' -f2)
            profile_name=$(basename "$profile_path")
            
            # Try to get Name field
            name_line=$(grep -B5 "^Path=$profile_path$" "$ini_path" | grep "^Name=" | tail -1)
            if [[ -n "$name_line" ]]; then
                profile_name=$(echo "$name_line" | cut -d'=' -f2)
            fi
            
            profiles+=("$profile_name:$zen_base/$profile_path")
            echo "Profile: $profile_name -> $zen_base/$profile_path"
        fi
    done < <(grep "^Path=" "$ini_path")
    
    echo ""
    echo "=== Final profiles array ==="
    printf '%s\n' "${profiles[@]}"
    echo ""
    echo "Number of profiles: ${#profiles[@]}"
fi
