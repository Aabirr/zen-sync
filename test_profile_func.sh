#!/bin/bash

# Test the profile detection function directly
echo "=== Testing Profile Detection Function ==="

# Source the function without running main script
source zen-sync-no-gpg.sh > /dev/null 2>&1

# Test the profile detection
profiles=($(get_zen_profile_paths))
echo "Found ${#profiles[@]} profiles:"

for i in "${!profiles[@]}"; do
    echo "  [$((i+1))] ${profiles[i]}"
done

if [[ ${#profiles[@]} -gt 1 ]]; then
    echo ""
    echo "=== Profile Selection Display ==="
    echo "Found ${#profiles[@]} Zen Browser profiles:"
    
    for i in "${!profiles[@]}"; do
        profile_name=$(echo "${profiles[i]}" | cut -d':' -f1)
        profile_path=$(echo "${profiles[i]}" | cut -d':' -f2)
        echo "  [$((i+1))] $profile_name"
        echo "      $profile_path"
    done
fi
