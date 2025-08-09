#!/bin/bash

# Debug the main script flow to see why profile list isn't visible
echo "=== Debug Main Script Flow ==="

# Source the functions from the main script
source zen-sync-no-gpg.sh > /dev/null 2>&1 || true

# Test the select_profile function directly
echo "Testing select_profile function:"
echo "================================"

# Mock the prerequisites and config functions to avoid errors
test_prerequisites() { return 0; }
get_config() { echo "null"; }
initialize_repository() { echo '{"repositoryUrl":"test","repositoryDir":"test"}'; }

# Test select_profile
result=$(select_profile)
echo "Result: $result"
echo "Exit code: $?"
