#!/bin/bash

# Test the actual select_profile function
# We'll simulate the environment

# Source the function
source zen-sync-no-gpg.sh

echo "Testing select_profile function..."
echo "================================="

# Test if we can call select_profile directly
# Since get_zen_profile_paths is defined in the script, we need to test it

# Test the actual get_zen_profile_paths function
profiles_detected=()
while IFS= read -r line; do
    [[ -n "$line" ]] && profiles_detected+=("$line")
done < <(get_zen_profile_paths)

echo "Found ${#profiles_detected[@]} profiles:"
for profile in "${profiles_detected[@]}"; do
    echo "  $profile"
done

if [[ ${#profiles_detected[@]} -gt 0 ]]; then
    echo "Profile detection is working"
else
    echo "No profiles detected"
fi
