#!/bin/bash

# Debug profile detection
set -x  # Enable debug mode

echo "=== Debug Profile Detection ==="

# Check if profiles.ini exists
profiles_ini="$HOME/.zen/profiles.ini"
echo "Checking: $profiles_ini"

if [[ -f "$profiles_ini" ]]; then
    echo "profiles.ini exists"
    echo "Contents:"
    cat "$profiles_ini"
    echo ""
    
    echo "=== Raw Profile Detection ==="
    awk '
        /^Name=/ { name=$0; sub(/^Name=/, "", name); current_name=name }
        /^Path=/ { path=$0; sub(/^Path=/, "", path); current_path=path }
        current_name && current_path {
            print current_name":"ENVIRON["HOME"]"/.zen/"current_path
            current_name=""
            current_path=""
        }
    ' "$profiles_ini"
    
    echo ""
    echo "=== Testing Array Population ==="
    profiles=()
    while IFS= read -r profile; do
        [[ -n "$profile" ]] && profiles+=("$profile")
    done < <(awk '
        /^Name=/ { name=$0; sub(/^Name=/, "", name); current_name=name }
        /^Path=/ { path=$0; sub(/^Path=/, "", path); current_path=path }
        current_name && current_path {
            print current_name":"ENVIRON["HOME"]"/.zen/"current_path
            current_name=""
            current_path=""
        }
    ' "$profiles_ini")
    
    echo "Found ${#profiles[@]} profiles:"
    printf '%s\n' "${profiles[@]}"
    
else
    echo "profiles.ini NOT found"
fi
