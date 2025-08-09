#!/bin/bash

echo "=== Simple Profile Debug ==="

# Test just the profile detection part
zen_base="$HOME/.zen"
ini_path="$zen_base/profiles.ini"

if [[ -f "$ini_path" ]]; then
    echo "Found profiles.ini at: $ini_path"
    
    # Test the awk command directly
    echo "Running awk command..."
    profiles_output=$(awk '
        /^Name=/ { name=$0; sub(/^Name=/, "", name); current_name=name }
        /^Path=/ { path=$0; sub(/^Path=/, "", path); current_path=path }
        current_name && current_path {
            print current_name":"zen_base"/"current_path
            current_name=""
            current_path=""
        }
    ' zen_base="$zen_base" "$ini_path")
    
    echo "Awk output:"
    echo "$profiles_output"
    
    # Test array population
    profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profiles+=("$line")
    done <<< "$profiles_output"
    
    echo "Array populated with ${#profiles[@]} profiles:"
    for i in "${!profiles[@]}"; do
        echo "  [$((i+1))] ${profiles[i]}"
    done
    
    # Test the display logic
    if [[ ${#profiles[@]} -gt 1 ]]; then
        echo ""
        echo "Profile selection display:"
        echo "Found ${#profiles[@]} Zen Browser profiles:"
        
        for i in "${!profiles[@]}"; do
            profile_name=$(echo "${profiles[i]}" | cut -d':' -f1)
            profile_path=$(echo "${profiles[i]}" | cut -d':' -f2)
            echo "  [$((i+1))] $profile_name"
            echo "      $profile_path"
        done
    fi
else
    echo "profiles.ini not found at: $ini_path"
fi
