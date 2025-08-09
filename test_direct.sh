#!/bin/bash

# Direct test of profile functions
echo "=== Direct Profile Test ==="

# Test get_zen_profile_paths directly
get_zen_profile_paths() {
    local profiles=()
    
    # Check for regular Zen Browser profiles
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - check standard and flatpak paths
        zen_bases=("$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen")
        
        for zen_base in "${zen_bases[@]}"; do
            ini_path="$zen_base/profiles.ini"
            
            if [[ -f "$ini_path" ]]; then
                # Read all profiles from profiles.ini
                while IFS= read -r path_line; do
                    if [[ "$path_line" =~ ^Path= ]]; then
                        profile_path=$(echo "$path_line" | cut -d'=' -f2)
                        profile_name=$(basename "$profile_path")
                        
                        # Also check if there's a Name= field
                        name_line=$(grep -B5 "^Path=$profile_path$" "$ini_path" | grep "^Name=" | tail -1)
                        if [[ -n "$name_line" ]]; then
                            profile_name=$(echo "$name_line" | cut -d'=' -f2)
                        fi
                        
                        profiles+=("$profile_name:$zen_base/$profile_path")
                    fi
                done < <(grep "^Path=" "$ini_path")
                break
            fi
        done
    fi
    
    printf '%s\n' "${profiles[@]}"
}

# Test the actual detection
echo "Testing profile detection..."
profiles_detected=($(get_zen_profile_paths))

echo "Found ${#profiles_detected[@]} profiles:"
for i in "${!profiles_detected[@]}"; do
    echo "  [$((i+1))] ${profiles_detected[i]}"
done

# Test select_profile logic
echo ""
echo "=== Testing select_profile logic ==="
if [[ ${#profiles_detected[@]} -gt 1 ]]; then
    echo "Multiple profiles detected - would prompt for selection"
    for i in "${!profiles_detected[@]}"; do
        profile_name=$(echo "${profiles_detected[i]}" | cut -d':' -f1)
        profile_path=$(echo "${profiles_detected[i]}" | cut -d':' -f2)
        echo "  [$((i+1))] $profile_name"
        echo "      $profile_path"
    done
else
    echo "Single profile detected - would auto-select"
fi
