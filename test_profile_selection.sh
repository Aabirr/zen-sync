#!/bin/bash

# Test profile selection
echo "Testing profile detection..."

# Simulate get_zen_profile_paths
get_zen_profile_paths() {
    echo "z9s769x5.Default:/home/aabir/.zen/z9s769x5.Default Profile"
    echo "r8sqpkaf.Default:/home/aabir/.zen/r8sqpkaf.Default (twilight)"
}

# Test select_profile function
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
    
    echo "DEBUG: Found ${#profiles[@]} profiles"
    echo "DEBUG: Profile names: ${profile_names[@]}"
    echo "DEBUG: Profile paths: ${profile_paths[@]}"
    
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
    
    echo "Would prompt for selection here"
    echo "Returning first profile for testing"
    echo "${profile_paths[0]}"
}

# Test the function
result=$(select_profile)
echo "Selected profile: $result"
