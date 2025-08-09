#!/bin/bash

# Test the fixed profile detection
echo "=== Testing Fixed Profile Detection ==="

# Simulate the fixed get_zen_profile_paths function
get_zen_profile_paths() {
    local profiles=()
    
    # Check for regular Zen Browser profiles
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - check standard and flatpak paths
        zen_bases=("$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen")
        
        for zen_base in "${zen_bases[@]}"; do
            ini_path="$zen_base/profiles.ini"
            
            if [[ -f "$ini_path" ]]; then
                # Use awk to properly extract profile names and paths
                awk -F'=' '
                    /^Name=/ {name=$2}
                    /^Path=/ {path=$2}
                    name && path {
                        print name":"zen_base"/"path
                        name=""
                        path=""
                    }
                ' zen_base="$zen_base" "$ini_path" | while IFS= read -r profile; do
                    [[ -n "$profile" ]] && echo "$profile"
                done
                break
            fi
        done
    fi
}

# Test the actual detection
echo "Running profile detection..."
profiles_detected=($(get_zen_profile_paths))

echo "Found ${#profiles_detected[@]} profiles:"
for i in "${!profiles_detected[@]}"; do
    echo "  [$((i+1))] ${profiles_detected[i]}"
done

# Test the select_profile simulation
if [[ ${#profiles_detected[@]} -gt 1 ]]; then
    echo ""
    echo "=== Profile Selection Prompt ==="
    echo "Found ${#profiles_detected[@]} Zen Browser profiles:"
    
    for i in "${!profiles_detected[@]}"; do
        profile_name=$(echo "${profiles_detected[i]}" | cut -d':' -f1)
        profile_path=$(echo "${profiles_detected[i]}" | cut -d':' -f2)
        echo "  [$((i+1))] $profile_name"
        echo "      $profile_path"
    done
    echo ""
    echo "Profile selection prompt should display correctly now."
fi
