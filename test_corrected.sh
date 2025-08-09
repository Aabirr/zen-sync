#!/bin/bash

# Test the corrected profile detection
echo "=== Testing Corrected Profile Detection ==="

# Test the corrected get_zen_profile_paths function
get_zen_profile_paths() {
    local profiles=()
    
    # Check for regular Zen Browser profiles
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux - check standard and flatpak paths
        zen_bases=("$HOME/.zen" "$HOME/.var/app/app.zen_browser.zen/.zen")
        
        for zen_base in "${zen_bases[@]}"; do
            ini_path="$zen_base/profiles.ini"
            
            if [[ -f "$ini_path" ]]; then
                # Parse profiles.ini correctly
                current_name=""
                current_path=""
                
                while IFS= read -r line; do
                    if [[ "$line" =~ ^Name= ]]; then
                        current_name=$(echo "$line" | cut -d'=' -f2)
                    elif [[ "$line" =~ ^Path= ]]; then
                        current_path=$(echo "$line" | cut -d'=' -f2)
                        
                        if [[ -n "$current_name" && -n "$current_path" ]]; then
                            profiles+=("$current_name:$zen_base/$current_path")
                            current_name=""
                            current_path=""
                        fi
                    fi
                done < "$ini_path"
                break
            fi
        done
    fi
    
    printf '%s\n' "${profiles[@]}"
}

# Test the actual detection
echo "Running corrected profile detection..."
profiles_detected=($(get_zen_profile_paths))

echo "Found ${#profiles_detected[@]} profiles:"
for i in "${!profiles_detected[@]}"; do
    echo "  [$((i+1))] ${profiles_detected[i]}"
done

# Test the select_profile simulation
if [[ ${#profiles_detected[@]} -gt 1 ]]; then
    echo ""
    echo "=== Corrected Profile Selection ==="
    echo "Found ${#profiles_detected[@]} Zen Browser profiles:"
    
    for i in "${!profiles_detected[@]}"; do
        profile_name=$(echo "${profiles_detected[i]}" | cut -d':' -f1)
        profile_path=$(echo "${profiles_detected[i]}" | cut -d':' -f2)
        echo "  [$((i+1))] $profile_name"
        echo "      $profile_path"
    done
fi
