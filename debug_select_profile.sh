#!/bin/bash

# Debug the select_profile function step by step
echo "=== Debug Select Profile ==="

# Mock the get_zen_profile_paths function temporarily
get_zen_profile_paths() {
    echo "Default Profile:/home/aabir/.zen/z9s769x5.Default Profile"
    echo "Default (twilight):/home/aabir/.zen/r8sqpkaf.Default (twilight)"
}

# Test select_profile logic
select_profile() {
    echo "Detecting Zen Browser profiles..."
    
    # Get profiles and store in array
    profiles=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && profiles+=("$line")
    done < <(get_zen_profile_paths)
    
    echo "Raw profiles array: ${profiles[@]}"
    echo "Number of profiles: ${#profiles[@]}"
    
    if [[ ${#profiles[@]} -eq 0 ]]; then
        echo "Error: No Zen Browser profiles found."
        return 1
    fi
    
    if [[ ${#profiles[@]} -eq 1 ]]; then
        profile_path=$(echo "${profiles[0]}" | cut -d':' -f2)
        echo "Using single profile: ${profiles[0]}"
        echo "$profile_path"
        return
    fi
    
    echo ""
    echo "Found ${#profiles[@]} Zen Browser profiles:"
    
    # Display profiles
    for i in "${!profiles[@]}"; do
        profile_name=$(echo "${profiles[i]}" | cut -d':' -f1)
        profile_path=$(echo "${profiles[i]}" | cut -d':' -f2)
        echo "  [$((i+1))] $profile_name"
        echo "      $profile_path"
    done
    
    echo ""
    echo "Profile selection should display here"
}

# Test the function
select_profile
